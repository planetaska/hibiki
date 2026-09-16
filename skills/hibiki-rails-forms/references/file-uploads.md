# File uploads (`hibiki:rails:upload_field`)

An Active Storage attachment on both edit surfaces of a scaffolded resource.
Both use direct upload; they differ in when: the classic page form uploads on
submit, the inline channel form uploads the moment a file is picked, and only
the signed blob id ever crosses the cable (a File cannot ride JSON).

## Generator

```sh
bin/rails g hibiki:rails:upload_field Album cover
bin/rails g hibiki:rails:upload_field Report document --accept=pdf,doc
bin/rails g hibiki:rails:upload_field Album photos --many
```

Owner must exist, be migrated, and be a hibiki:rails scaffold. One attachment
per run; a second run adds a second attachment beside the first.

| Option | Effect |
| --- | --- |
| `--many` | `has_many_attached` gallery; implied by an existing `has_many_attached`; refuses against an existing `has_one_attached` |
| `--accept=LIST` | comma-separated tokens for both inputs (default `image`) |
| `--css=NAME` / `--phlex` | detected from the scaffold when absent |

| `--accept` token | Attribute value |
| --- | --- |
| `image` / `audio` / `video` | `image/*` / `audio/*` / `video/*` |
| `pdf` / `csv` / `text` | `application/pdf` / `text/csv` / `text/plain` |
| `doc` / `xls` / `ppt` | `.doc,.docx` / `.xls,.xlsx` / `.ppt,.pptx` |
| `type/subtype` or `.ext` | passed through |

Unknown tokens refuse before writing. The list is advisory; display sites
branch per blob at render time (`blob.variable?` gets a thumbnail, anything
else its filename and size).

## What lands where

| Written or modified | Content |
| --- | --- |
| `app/channels/concerns/albums_channel/cover_upload.rb` | module `AlbumsChannel::CoverUpload` |
| `app/views/albums/_cover_upload.html.erb` | the upload row, locals `(form:, dom:, extras: {})` |
| `app/javascript/controllers/upload_field_controller.js` | once per app, registered as `upload-field`; refreshed by a `--many` run against a pre-gallery copy |
| `app/channels/albums_channel.rb` | `include CoverUpload` |
| `app/models/album.rb` | `has_one_attached :cover`; `attribute :remove_cover, :boolean, default: false`; guarded `after_save` purge |
| `app/queries/album_query.rb`, `app/channels/album_channel.rb` | `.with_attached_cover` |
| `_album.html.erb`, `_album_form.html.erb`, `_form.html.erb` | display line; render call; `direct_upload: true` field plus Remove checkbox |
| `app/controllers/albums_controller.rb` | `:cover, :remove_cover` in `params.expect` (`--many`: `add_photos: [], remove_photo_ids: []`) |

Notices: `many`, `migrate` (no Active Storage tables), `gem`
(`image_processing` when images are accepted), `importmap` (pin
`@rails/activestorage`), `js` (`ActiveStorage.start()` missing from
`application.js`), `restart` (`app/channels/concerns` is new).

## Inline flow: pick, upload, attach on save

The input has no `name` and carries Stimulus values `url`, `action`, `dom`:

```js
const blob = await this.directUpload(file)
const accepted = blob && performOn(this.element, this.actionValue, {
  dom: this.domValue, signed_id: blob.signed_id, filename: file.name
})
if (!accepted) this.element.value = ""   // island offline, nothing queued
```

The concern (prepended `GraphHooks` wrap `build_graph`, `edit`, `cancel`,
`save`, `new_form`, `cancel_new`, `create`, `list_locals` with `super`):

| Name | Role |
| --- | --- |
| `@pending_cover` | `Hibiki::State.new({})`, `{ "album_5" => { signed_id:, filename: } or { remove: true } }`, written whole |
| `set_cover(data)` | action; payload `dom`, `signed_id`, `filename` |
| `remove_cover(data)` | action; marks `{ remove: true }` when attached, else discards the pending pick |
| `cover_upload_form(dom)` | private; `album_new` to `@new_form` while creating, `album_<id>` to `@form` while editing |
| `update_pending_cover(dom, value)` | private; merge or except, so the signal fires |
| `apply_pending_cover(dom, record)` | private; after a successful save: `attach(signed_id)` or `purge` on a fresh `find_by`, then `invalidate` |

`--many` keeps `{ adds: [...], removes: [attachment_id] }` per dom, with
`add_photos(data)` appending and `remove_photos(data)` dropping a pending
`signed_id` or toggling an `attachment_id` mark; save appends via
`attach(*ids)` and purges marked rows.

## Classic form

```ruby
attribute :remove_cover, :boolean, default: false
after_save(if: -> { remove_cover && attachment_changes["cover"].nil? }) { cover.purge }
```

A same-submit upload wins over the checkbox. `--many` never assigns the
collection (Rails 7.1+ replaces it): `attribute :add_photos` appends in
`before_save`, `attribute :remove_photo_ids, default: -> { [] }` purges in
`after_save`.

## Rules

- Read `album.cover_attachment` / `photos_attachments` on channel rows; the
  `album.cover` proxy memoizes and raises `FrozenError` on a frozen row.
- Keep `with_attached_cover` in both queries; rows are `strict_loading`.
- Attach only after a successful save and through a fresh find.

Full docs: https://planetaska.github.io/hibiki/file-uploads/
