---
title: File uploads
nav_order: 5
---

# File uploads

A resource the [CRUD scaffold]({{ "/crud-scaffolding/" | relative_url }})
generated can be edited in two places. The classic `new` and `edit` pages
submit a form over HTTP, the way every Rails app does. The index page is an
*island* — a region of the page kept live by a channel, the WebSocket
connection the scaffold set up — and its inline forms save by serializing
their fields and sending them over that channel. An attachment has to work on
both surfaces, and they cannot share one mechanism: an HTTP form carries a
file in its request body, but a channel message is JSON, and a `File` cannot
ride in it.

Active Storage's *direct upload* serves both. The browser uploads the file
straight to storage and gets back a **signed id** — a short token that stands
for the stored blob; attaching the file to a record later takes only that
token. The two forms differ in *when* they upload. The classic form uploads
on submit, swapping the signed id into the field before the form goes. The
inline form uploads the moment a file is picked, and only the signed id ever
crosses the cable.

## Single file upload

`hibiki:rails:upload_field` adds one attachment to a resource the CRUD
scaffold already generated, on both surfaces:

```sh
bin/rails g hibiki:rails:upload_field Album cover
```

`Album` must exist, be migrated, and be a hibiki:rails scaffold — the inline
form and the collection channel are what the upload extends. Each run adds
one attachment; a second run adds a second attachment beside the first.

## What lands where

The generated code has two halves: a channel concern — the server side, mixed
into the resource's channel — and a view partial for the upload row in the
inline form. A Stimulus controller, shared by every upload field in the app,
does the browser-side uploading. The rest of the run is small edits to files
the scaffold already generated:

| File | What happens |
| --- | --- |
| `app/channels/concerns/albums_channel/cover_upload.rb` | **Created.** The whole channel half, as a concern |
| `app/views/albums/_cover_upload.html.erb` | **Created.** The inline form's upload row (a Phlex component under `--phlex`) |
| `app/javascript/controllers/upload_field_controller.js` | **Created once per app.** The direct-upload Stimulus controller every upload field shares |
| `app/channels/albums_channel.rb` | One line: `include CoverUpload` |
| `app/models/album.rb` | `has_one_attached :cover`, plus the classic form's `remove_cover` virtual attribute and its guarded purge |
| `app/models/album_query.rb`, `app/channels/album_channel.rb` | `.with_attached_cover` — the channel's rows are `strict_loading`, so the blob must be preloaded |
| `_album.html.erb` / row component | A "Cover: …" display line — a thumbnail, or the filename linked to the blob |
| `_album_form.html.erb` / row form component | The render call for the upload row |
| `_form.html.erb` / page form component | A `direct_upload: true` file field and a "Remove cover" checkbox |
| `app/controllers/albums_controller.rb` | `:cover, :remove_cover` appended to `params.expect` |

The include line is the channel's only edit; everything else the concern
does, it does from inside. It wraps the channel's `build_graph`,
`edit`/`cancel`/`save`, and inline-create actions through a prepended module
that calls `super`, and its public `set_cover` / `remove_cover` methods
become client-invocable actions, exactly as if they were defined on the
channel class. Everything it adds carries the attachment's name
(`@pending_cover`, `update_pending_cover`), so a second attachment's concern
coexists with the first in the same channel.

## The inline form: upload on pick, attach on save

The inline form's file input carries **no `name`**, on purpose: the file must
never enter the form's submit payload. Picking a file instead fires the
shared Stimulus controller, which direct-uploads it to storage right there
and hands the island the result — the signed id and the filename, nothing
more:

```js
// upload_field_controller.js — one controller, parameterized by the
// action and dom the view stamped on the input
const accepted = performOn(this.element, this.actionValue, {
  dom: this.domValue, signed_id: blob.signed_id, filename: file.name
})
if (!accepted) this.element.value = ""   // island offline: nothing was queued
```

On the server, the concern holds that pending upload in the island's *signal
graph* — the server-side state the page re-renders from ([reactive
forms]({{ "/reactive-forms/" | relative_url }}) introduces it; here it is
enough that writing a signal repaints the island). The entry is keyed by the
form's `dom`, the identifier naming which open form the pick belongs to, so a
row's edit form and the inline create form can be open at the same time:

```ruby
# { "album_5" => { signed_id:, filename: } or { remove: true } } — written
# whole, so the signal fires on every change
@pending_cover = Hibiki::State.new({})

def set_cover(data)
  dom = data["dom"].to_s
  return unless cover_upload_form(dom)          # which open form, or none

  update_pending_cover(dom, { signed_id: data["signed_id"].to_s,
                              filename: data["filename"].to_s })
end
```

Keeping the pending upload in the graph is what makes the "attaches on save"
badge honest. Every repaint re-renders the badge from the signal, so it
survives a morph; and each open form keys its own entry, so a row edit and
the inline create form hold independent pending files without either losing
the other's. The record itself is touched only after a **successful** save:
the concern captures the editing id before handing off to the scaffold's
save, acts only when that save cleared it, and attaches through a fresh
find — never through the frozen row.

Remove is the same shape in reverse. The form's Remove button writes
`{ remove: true }` into the same signal, the badge reads "cover removed on
save", and the purge happens at commit. Picking a new file overrides the
mark.

## The classic form: upload on submit

The page form uses Rails' own machinery: a named file field with
`direct_upload: true`, which `ActiveStorage.start()` uploads on submit,
swapping the signed id in before the form goes. Remove is a checkbox backed
by a virtual attribute on the model:

```ruby
attribute :remove_cover, :boolean, default: false
after_save(if: -> { remove_cover && attachment_changes["cover"].nil? }) { cover.purge }
```

The `attachment_changes` guard decides a same-submit conflict: when one
submit carries a new file **and** a checked box, the upload wins.

## Multiple files: `--many`

```sh
bin/rails g hibiki:rails:upload_field Album photos --many
```

generates the `has_many_attached` shape instead. A model that already
declares `has_many_attached :photos` selects it by itself, and `--many`
against an existing `has_one_attached` refuses. The inline input takes
several files and uploads them one after another, so the pending list keeps
the pick order. Each pending file gets its own badge with a ✕ to drop it,
and each file already attached gets a ✕ that marks it for removal —
"removed on save", with Undo. The marks live in the graph beside the pending
adds, `{ adds: [...], removes: [...] }` per form dom, and a successful save
applies both: the adds are **appended** through `attach`, the marked files
purged.

Appended is the design's one Rails-specific decision. Since Rails 7.1,
*assigning* to a `has_many_attached` replaces the whole collection — so
`album.update(photos: [...])` from a page form that uploads one more photo
would silently purge the rest. The classic form therefore never assigns the
collection. It rides two virtual attributes instead:

```ruby
attribute :add_photos
attribute :remove_photo_ids, default: -> { [] }
before_save(if: -> { add_photos.present? }) { photos.attach(*add_photos) }
after_save(if: -> { remove_photo_ids.present? }) { photos_attachments.where(id: remove_photo_ids).each(&:purge) }
```

— a `multiple` direct-upload field named `add_photos`, and a "Remove"
checkbox per attached file feeding `remove_photo_ids`. `params.expect` takes
them as `{ add_photos: [], remove_photo_ids: [] }`.

## Choosing file types: `--accept`

```sh
bin/rails g hibiki:rails:upload_field Report document --accept=pdf,doc
```

sets the `accept` attribute on both file inputs — the hint the browser's
file picker uses to filter what it offers. Each token stands for what the
picker understands: a MIME pattern, or an extension list where the MIME
names would be unreadable (like the Office formats):

| Token | What the `accept` attribute gets |
| --- | --- |
| `image` (the default) | `image/*` |
| `audio` | `audio/*` |
| `video` | `video/*` |
| `pdf` | `application/pdf` |
| `csv` | `text/csv` |
| `text` | `text/plain` |
| `doc` | `.doc,.docx` |
| `xls` | `.xls,.xlsx` |
| `ppt` | `.ppt,.pptx` |
| any `type/subtype` | passed through as written — `application/zip` |
| any `.ext` | passed through as written — `.svg` |

Tokens join in the order given, so `--accept=pdf,doc` emits the same string
on both inputs:

```erb
<%= form.file_field :document, accept: "application/pdf,.doc,.docx", direct_upload: true %>
```

An unknown token refuses before anything is written. The list is
**advisory** — browsers honor it, but nothing enforces it — so every display
site decides per blob at render time: an image (`blob.variable?`) gets a
variant thumbnail; anything else shows its filename and size, linked to the
blob.

## Options

| Option | Effect |
| --- | --- |
| `--many` | A `has_many_attached` gallery (implied by an existing `has_many_attached`) |
| `--accept=LIST` | Comma-separated file types for both inputs (default `image`) |
| `--css=NAME` | `daisyui`, `tailwind` or `none` — detected the same way the scaffold detects it |
| `--phlex` | A Phlex component instead of the ERB partial. Absent means detect from what the scaffold left |

## Notes

- **Channel rows are frozen and `strict_loading`.** The generated views read
  `album.cover_attachment` (or `photos_attachments`), never the `album.cover`
  proxy — the proxy memoizes into an ivar and raises `FrozenError` on a
  frozen row — and both channel queries preload with `with_attached_cover`.
  Keep both if you reshape the views.
- The generator warns about, and never installs, three prerequisites: the
  Active Storage tables (`bin/rails active_storage:install` + migrate), the
  `image_processing` gem for thumbnails (only when an image type is
  accepted), and `ActiveStorage.start()` in the JS entrypoint, which the
  classic form's direct upload needs. Importmap apps also need the
  `@rails/activestorage` pin.
- `app/channels/concerns` is a new autoload directory on its first use —
  restart the server.
- The shared `upload_field_controller.js` is written once per app. A
  `--many` run against a copy from before galleries (one file per pick)
  refreshes it and says so; single-attachment runs leave an existing file
  alone.
