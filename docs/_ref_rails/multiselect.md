---
title: Multi-select associations
nav_order: 3
---

# Multi-select associations

A `has_many :through` on an edit screen wants to be a multi-select: check the
songs, save, and the join rows follow. On a reactive resource there is a second
requirement a classic `<select multiple>` never had to meet — the option list
can be *searched*, live, and narrowing it must never drop a selection it
happens to hide.

`hibiki:rails:multiselect` adds that dropdown onto a resource the
[CRUD scaffold]({{ "/crud-scaffolding/" | relative_url }}) already generated:

```sh
bin/rails g hibiki:rails:multiselect Album Song Track
```

`Album` (the owner) and `Song` (the target) must exist and be migrated. `Track`
— the join — is the one model the generator may **create**: when it doesn't
exist you get the model and its migration, a `belongs_to` pair with a unique
index over it, and the `has_many :through` injected into the owner. When the
owner already declares `has_many :songs, through: :tracks`, the third argument
can be dropped — the join is read off the reflection.

## What lands where

| File | What happens |
| --- | --- |
| `app/channels/concerns/albums_channel/songs_multiselect.rb` | **Created.** The whole channel half, as a concern |
| `app/views/albums/_songs_multiselect.html.erb` | **Created.** The dropdown (a Phlex component under `--phlex`) |
| `app/models/track.rb` + migration | **Created if missing** — otherwise `touch: true` is added to its `belongs_to :album` |
| `app/channels/albums_channel.rb` | One line: `include SongsMultiselect` |
| `app/forms/album_form.rb` | One declaration: `reactive_association :songs` |
| `app/models/album.rb` | The `has_many` pair, if not already declared |
| `app/models/album_query.rb`, `app/channels/album_channel.rb` | `includes(:songs)` — the rows are `strict_loading`, so the labels must be preloaded |
| `_album.html.erb` / row component | A "Songs: …" display line |
| `_album_form.html.erb` / row form component | The render call for the dropdown |

The include line is the channel's **only** edit. The concern wraps
`build_graph`, `list_locals` and `edit` with `super` through a prepended
module, and its public `toggle_song` / `search_songs` methods become
client-invocable actions exactly like methods on the channel class. Everything
it adds is namespaced by the target (`@songs_query`, `@songs_options`,
`toggle_song`), so a second multiselect on the same channel coexists with the
first.

## The selection lives in the graph

The generated checkboxes are deliberately **not** named `song_ids[]`. Each one
sends its own action, carrying its checked state:

```ruby
# One checkbox toggled: a SET, not a toggle — the client sends the box's
# checked state, so two tabs converge.
def toggle_song(data)
  return unless @editing_id.peek

  # Untrusted id — resolve it against the table before it enters the form.
  id = Song.where(id: data["id"]).pick(:id)
  return unless id

  ids = @form.song_ids
  @form.song_ids = data["checked"] ? ids | [id] : ids - [id]
end
```

The form's `song_ids` signal is the selection; the submit payload never
carries it. That one decision is what makes the searchable filter honest: the
filter narrows the *option list*, and a save while forty of your fifty checked
songs are filtered out of view still commits all fifty. A form-submit design
(`song_ids[]` collected at save time) would silently drop everything the
filter hid.

It is also why two tabs editing the same row converge — each toggle is a set
("this song is checked"), not a flip.

## Search and the option cap

The dropdown's filter input drives `search_songs`, which writes a query
signal; the options derived narrows on it server-side, so 100k songs never
reach the page. The list is capped (`OPTIONS_LIMIT` in the concern, `--limit`
to choose it) with a `LIMIT+1` fetch — the extra row becomes the
"Showing first 50 — type to narrow" hint, so no COUNT runs per keystroke.

`--skip-search` omits the filter input *and* the cap: a cap without a search
box would strand the options it hides. Use it when the option set is small and
enumerable.

## `reactive_association` by itself

The form-side half is an ordinary
[ReactiveForm]({{ "/reactive-forms/" | relative_url }}) macro, usable without
the generator:

```ruby
class AlbumForm
  include Hibiki::Rails::ReactiveForm

  reactive_attributes Album, :title, :release_date
  reactive_association :songs          # defines the song_ids signal
end
```

`hydrate` reads the record's own `song_ids`; `commit` hands the ids to
`#update`, where ActiveRecord's association writer does the join-row
bookkeeping. Each id is cast through the *target* model's primary-key type
(channel payloads are strings), and the multi-select hidden-input blank is
dropped — without that, the signal would hold wire strings against an integer
snapshot and `dirty?` would report dirty forever.

For a hand-rolled form that does submit its selection, the client collects
every entry of a `[]`-suffixed field name as an array under the bare key — a
`<select multiple name="song_ids[]">` or a checkbox group reaches your action
as `data["song_ids"]`, a real array. Duplicate keys *without* the suffix stay
last-wins, which is what Rails' hidden-field checkbox convention depends on.

## Options

| Option | Effect |
| --- | --- |
| `--skip-search` | No filter input — and no option cap, which would strand options |
| `--limit=N` | How many options the dropdown offers at once (default 50) |
| `--label=COLUMN` | The target column shown per option. Absent means infer: `name`/`title`/`label`/`email`, then the first string column |
| `--css=NAME` | `daisyui`, `tailwind` or `none` — detected like the scaffold's. Under `none` the panel has nothing to hide it and renders as an inline list |
| `--phlex` | A Phlex component instead of the ERB partial. Absent means detect from what the scaffold left |

## Notes

- **`touch: true` on the join is load-bearing.** A join-row write bumps the
  owner's `updated_at`, which fires the owner's `after_commit` ping — that is
  how a save in one session reaches every open index and show page.
- When the join was generated, run `bin/rails db:migrate` before using the
  dropdown; and `app/channels/concerns` is a new autoload directory on its
  first use, so restart the server.
- Scaffolds generated before 0.7.0 predate the `extras:` hash the dropdown's
  locals ride on. The generator threads it through those partials itself and
  says so with a `compat` notice — nothing to do by hand unless you had
  reshaped the partials, in which case the notice tells you what to pass.
