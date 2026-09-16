# Multi-select associations (`reactive_association` + `hibiki:rails:multiselect`)

A searchable checkbox dropdown over a `has_many :through`, where the graph
owns the selection so narrowing the option list can never drop a checked id.

## Form side, usable alone

```ruby
class AlbumForm
  include Hibiki::Rails::ReactiveForm
  reactive_attributes Album, :title, :release_date
  reactive_association :songs   # song_ids signal; must follow reactive_attributes
end
```

Hydrate reads `record.song_ids`; commit passes `song_ids:` to `update`, where
ActiveRecord's association writer manages join rows. Each id is cast through
`Song`'s primary-key type and the multi-select hidden-input blank is dropped
(`Array(value).compact_blank`), so wire strings never leave `dirty?` stuck.

A hand-rolled `<select multiple name="song_ids[]">` still works: the JS
client collects `[]`-suffixed names into one array under the bare key, so the
action reads `data["song_ids"]`.

## Generator

```sh
bin/rails g hibiki:rails:multiselect Album Song Track
bin/rails g hibiki:rails:multiselect Album Song --skip-search   # join read off has_many :through
```

Owner and target must exist and be migrated; the join is the one model it
may create (belongs_to pair, `touch: true` on the owner side, unique index
over the pair, `has_many :through` injected into the owner).

| Written or modified | Content |
| --- | --- |
| `app/channels/concerns/albums_channel/songs_multiselect.rb` | the concern, module `AlbumsChannel::SongsMultiselect` |
| `app/views/albums/_songs_multiselect.html.erb` | the dropdown, locals `(form:, dom:, extras: {})` (Phlex under `--phlex`) |
| `app/models/track.rb` + migration | created if missing; else `touch: true` added to `belongs_to :album` |
| `app/channels/albums_channel.rb` | `include SongsMultiselect` |
| `app/forms/album_form.rb` | `reactive_association :songs` |
| `app/models/album.rb` | the `has_many` pair if absent |
| `app/queries/album_query.rb`, `app/channels/album_channel.rb` | `includes(:songs)` (rows are `strict_loading`) |
| `_album.html.erb`, `_album_form.html.erb` | a "Songs:" display line; the render call |

| Option | Effect |
| --- | --- |
| `--skip-search` | no filter input and no cap (a cap without search strands options) |
| `--limit=N` | `OPTIONS_LIMIT` (default 50) |
| `--label=COLUMN` | option label; default infers `name`/`title`/`label`/`email`, then the first string column, else refuses |
| `--css=NAME` / `--phlex` | detected from the scaffold when absent; under `none` the panel renders inline |

Notices: `migrate` (join generated), `restart` (`app/channels/concerns` is
new), `assoc` (label guess), `compat` (pre-0.7.0 scaffolds get the `extras:`
hash threaded through).

## The concern

Signals on `build_graph`: `@songs_query` (`""`) and `@songs_options`, a
derived that reads `@db_version`, filters in SQL with `sanitize_sql_like`,
fetches `OPTIONS_LIMIT + 1` rows and returns `{ options:, truncated: }`.
`edit`/`new_form` reset the query. `list_locals` merges
`extras: { songs_multiselect: ... }` only while a form is open.

Actions:

```ruby
def toggle_song(data)                      # payload: dom, id, checked
  form = multiselect_form(data["dom"].to_s)
  return unless form

  id = Song.where(id: data["id"]).pick(:id)   # untrusted id, resolved first
  return unless id

  ids = form.song_ids
  form.song_ids = data["checked"] ? ids | [id] : ids - [id]   # a SET, not a flip
end

def search_songs(data) = @songs_query.value = data["query"].to_s
```

`multiselect_form(dom)` is private: `dom` ending `_new` resolves to
`@new_form` while `@creating`, otherwise `@form` while `@editing_id`. A
toggle at a closed form drops.

Rules: boxes are named `checked`, never `song_ids[]`, because the submit
payload must not carry a subset that depends on the filter. Sending the
box's state makes two tabs converge. `touch: true` on the join bumps the
owner's `updated_at`, whose `after_commit` ping reaches every open index.

Full docs: https://planetaska.github.io/hibiki/multiselect/
