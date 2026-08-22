---
title: File uploads
nav_order: 5
---

# File uploads

An attachment on a reactive resource has two edit surfaces to serve. The
classic page form can upload on submit the way Rails always has — Active
Storage's direct upload swaps a signed id into the field before the form goes.
The inline channel form cannot: its save serializes the form with `FormData`
and ships it over the cable, and a `File` does not ride a channel message.

## Single file upload

`hibiki:rails:upload_field` adds one attachment onto a resource the
[CRUD scaffold]({{ "/crud-scaffolding/" | relative_url }}) already generated,
on both surfaces:

```sh
bin/rails g hibiki:rails:upload_field Album cover
```

`Album` must exist, be migrated and be a hibiki:rails scaffold (the inline
form and the collection channel are what the upload extends). One attachment
per run; a second run adds a second attachment beside the first.

## What lands where

| File | What happens |
| --- | --- |
| `app/channels/concerns/albums_channel/cover_upload.rb` | **Created.** The channel half, as a concern |
| `app/views/albums/_cover_upload.html.erb` | **Created.** The inline form's upload row (a Phlex component under `--phlex`) |
| `app/javascript/controllers/upload_field_controller.js` | **Created once per app.** The direct-upload Stimulus controller every upload field shares |
| `app/channels/albums_channel.rb` | One line: `include CoverUpload` |
| `app/models/album.rb` | `has_one_attached :cover`, plus the classic form's `remove_cover` virtual attribute and its guarded purge |
| `app/models/album_query.rb`, `app/channels/album_channel.rb` | `.with_attached_cover` — the rows are `strict_loading`, so the blob must be preloaded |
| `_album.html.erb` / row component | A "Cover: …" display line — a thumbnail, or the filename linked to the blob |
| `_album_form.html.erb` / row form component | The render call for the upload row |
| `_form.html.erb` / page form component | A `direct_upload: true` file field and a "Remove cover" checkbox |
| `app/controllers/albums_controller.rb` | `:cover, :remove_cover` appended to `params.expect` |

The include line is the channel's only edit. The concern wraps
`build_graph`, `edit`/`cancel`/`save` and the inline-create actions with
`super` through a prepended module; its public `set_cover` / `remove_cover`
methods become client-invocable actions exactly like methods on the channel
class. Everything it adds is suffixed by the attachment (`@pending_cover`,
`update_pending_cover`), so a second attachment's concern coexists with the
first in the same channel.

## The inline form: only the signed id crosses the wire

The inline form's file input carries **no name** on purpose. Picking a file
fires the shared Stimulus controller, which direct-uploads it to storage right
there and hands the island's graph the result:

```js
// upload_field_controller.js — one controller, parameterized by the
// action and dom the view stamped on the input
const accepted = performOn(this.element, this.actionValue, {
  dom: this.domValue, signed_id: blob.signed_id, filename: file.name
})
if (!accepted) this.element.value = ""   // island offline: nothing was queued
```

The concern keeps that pending upload **in the graph**, keyed by the form's
dom:

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

Graph-owned is what makes the "attaches on save" badge honest: every repaint
re-renders it from the signal, so it survives a morph, and a row edit and the
inline create form — each with its own dom — hold independent pending files
without either losing the other's. The record is only touched after a
**successful** commit (the concern captures the editing id before `super` and
acts when `super` cleared it), via a fresh find, never the frozen row.

Remove is the same shape in reverse: the form's Remove button writes
`{ remove: true }`, the badge reads "cover removed on save", and the purge
happens at commit. A later pick overrides the mark.

## The classic form: Rails' own path

The page form gets a named field with `direct_upload: true` — `ActiveStorage.start()`'s
form machinery uploads on submit and swaps the signed id in — and a
"Remove cover" checkbox backed by a virtual attribute on the model:

```ruby
attribute :remove_cover, :boolean, default: false
after_save(if: -> { remove_cover && attachment_changes["cover"].nil? }) { cover.purge }
```

The `attachment_changes` guard is what decides a same-submit conflict: a new
file **and** a checked box means the upload wins.

## Multiple files upload: `--many`

```sh
bin/rails g hibiki:rails:upload_field Album photos --many
```

generates the `has_many_attached` shape instead — and a model that already
declares `has_many_attached :photos` selects it by itself (`--many` against an
existing `has_one_attached` refuses). The inline input takes several files,
uploaded one after another so the pending list keeps the pick order; each
pending file gets its own badge with a ✕ to drop it, and each file already
attached gets a ✕ that marks it for removal ("removed on save", with Undo).
The marks live in the graph with the pending adds — `{ adds: [...], removes:
[...] }` per form dom — and commit applies both: the adds are **appended**
through `attach`, the marked ids purged.

That word, appended, is the design's one Rails-specific decision. Since Rails
7.1, *assigning* to a `has_many_attached` replaces the whole collection — so
`album.update(photos: [...])` from a page form that uploads one more photo would
silently purge the rest. The classic form therefore never assigns the
collection. It rides two virtual attributes:

```ruby
attribute :add_photos
attribute :remove_photo_ids, default: -> { [] }
before_save(if: -> { add_photos.present? }) { photos.attach(*add_photos) }
after_save(if: -> { remove_photo_ids.present? }) { photos_attachments.where(id: remove_photo_ids).each(&:purge) }
```

— a `multiple` direct-upload field named `add_photos`, and a "Remove"
checkbox per attached file feeding `remove_photo_ids`. `params.expect` takes
them as `{ add_photos: [], remove_photo_ids: [] }`.

## Allowing other file types: `--accept`

```sh
bin/rails g hibiki:rails:upload_field Report document --accept=pdf,doc
```

narrows both file inputs' `accept` attribute. Each token stands for what the
browser's file picker understands — a MIME pattern, or an extension list
where the MIME names would be unreadable (like the Office formats):

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
**advisory** — browsers honor it, nothing enforces it — so every display site
decides per blob at render time: an image (`blob.variable?`) gets a variant
thumbnail, anything else its filename and size, linked to the blob on the row.

## Options

| Option | Effect |
| --- | --- |
| `--many` | A `has_many_attached` gallery (implied by an existing `has_many_attached`) |
| `--accept=LIST` | Comma-separated file types for both inputs (default `image`) |
| `--css=NAME` | `daisyui`, `tailwind` or `none` — detected like the scaffold's |
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
