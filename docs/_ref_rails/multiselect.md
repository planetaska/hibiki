---
title: Multi-select associations
nav_order: 4
---

# Multi-select associations

An album has many songs, a song appears on many albums, and a `Track` row
joins each pair. On a classic Rails form you edit an association like this
with a multi-select — a checkbox group or `<select multiple>` named
`song_ids[]` — and the checked ids are collected when the form is submitted.
That works until the option list grows: fifty songs fit on a screen, a
hundred thousand don't. Hibiki's version keeps the checkboxes but makes the
list *searchable*, live — and searching adds a requirement the classic
control never had to meet: narrowing the list must never lose a checked
selection it happens to hide.

`hibiki:rails:multiselect` builds that dropdown onto a resource the
[CRUD scaffold]({{ "/crud-scaffolding/" | relative_url }}) already generated:

```sh
bin/rails g hibiki:rails:multiselect Album Song Track
```

The three arguments are the owner, the target, and the join. `Album` and
`Song` must exist and be migrated. `Track` is the one model the generator may
**create**: when it doesn't exist you get the model and its migration — a
`belongs_to` for each side with a unique index over the pair — and the
`has_many :through` injected into the owner. When the owner already declares
`has_many :songs, through: :tracks`, the third argument can be dropped; the
generator reads the join off the association.

## What lands where

The generated code has two halves: a channel concern — the server side,
mixed into the resource's channel (the WebSocket connection the scaffold set
up) — and a view partial for the dropdown itself. The rest of the run is
one-line edits to files the scaffold already generated:

| File | What happens |
| --- | --- |
| `app/channels/concerns/albums_channel/songs_multiselect.rb` | **Created.** The whole channel half, as a concern |
| `app/views/albums/_songs_multiselect.html.erb` | **Created.** The dropdown (a Phlex component under `--phlex`) |
| `app/models/track.rb` + migration | **Created if missing** — otherwise `touch: true` is added to its `belongs_to :album` |
| `app/channels/albums_channel.rb` | One line: `include SongsMultiselect` |
| `app/forms/album_form.rb` | One declaration: `reactive_association :songs` |
| `app/models/album.rb` | The `has_many` pair, if not already declared |
| `app/models/album_query.rb`, `app/channels/album_channel.rb` | `includes(:songs)` — the scaffold's rows are `strict_loading`, so the song labels must be preloaded |
| `_album.html.erb` / row component | A "Songs: …" display line |
| `_album_form.html.erb` / row form component | The render call for the dropdown |

The include line is the channel's only edit; everything else the multi-select concern
does, it does from inside. Its public `toggle_song` and `search_songs`
methods become client-invocable actions, exactly as if they were defined on
the channel class, and everything it adds is namespaced by the target
(`@songs_query`, `@songs_options`, `toggle_song`) — so a second multiselect
on the same channel coexists with the first.

## The selection lives in the signal graph

In a [reactive form]({{ "/reactive-forms/" | relative_url }}), each field is
a *signal* — a server-side value the page reacts to. The
`reactive_association :songs` declaration gives the album's form one more:
`song_ids`, an array of the checked songs' ids. The generated checkboxes are
deliberately **not** named `song_ids[]`. Checking one doesn't stage a form
field for submit; it fires a channel action that writes the signal directly:

```ruby
# One checkbox toggled: a SET, not a toggle — the client sends the box's
# checked state, so two tabs converge. `dom` names the form the box
# belongs to — a row edit and the inline create form can be open at once.
def toggle_song(data)
  form = multiselect_form(data["dom"].to_s)
  return unless form

  # Untrusted id — resolve it against the table before it enters the form.
  id = Song.where(id: data["id"]).pick(:id)
  return unless id

  ids = form.song_ids
  form.song_ids = data["checked"] ? ids | [id] : ids - [id]
end
```

Because the selection lives on the server, the submit payload never carries
it — and that one decision is what makes the searchable filter honest. The
filter narrows the *option list*, nothing more. Save while forty of your
fifty checked songs are filtered out of view, and all fifty commit. A
form-submit design, collecting `song_ids[]` at save time, would silently
drop every selection the filter hid.

The `dom` value in the payload is how one action serves two forms. The
scaffold can have a row's edit form and the inline create form open side by
side, each with its own dropdown; every toggle names the form it belongs to,
so the two selections never cross-write, and a toggle aimed at a form that
is no longer open is dropped. ([Nested forms]({{ "/nested-forms/" |
relative_url }}) use the same convention.)

Sending the checkbox's state, rather than "flip this", is why two tabs
editing the same row converge: each toggle means "this song is checked", and
applying it twice is harmless.

## Search and the option cap

Typing in the dropdown's filter input fires `search_songs`, which writes the
text into a query signal on the server. The option list is a *derived* — a
value computed from other signals — that re-runs the database query whenever
the query signal changes. The narrowing happens in SQL, so a hundred
thousand songs never reach the page.

The list is capped — `OPTIONS_LIMIT` in the concern, `--limit` to choose it
at generation time. The concern fetches one row past the cap; when that
extra row comes back, it becomes the "Showing first 50 — type to narrow"
hint. No COUNT query runs per keystroke.

`--skip-search` omits the filter input *and* the cap together: a cap without
a search box would strand the options it hides, with no way to reach them.
Use it when the option set is small and enumerable.

## `reactive_association` without the generator

The form-side half is an ordinary [ReactiveForm]({{ "/reactive-forms/" |
relative_url }}) macro, usable on its own:

```ruby
class AlbumForm
  include Hibiki::Rails::ReactiveForm

  reactive_attributes Album, :title, :release_date
  reactive_association :songs          # defines the song_ids signal
end
```

Hydrating the form reads the record's own `song_ids`; commit hands the ids
to `#update`, where ActiveRecord's association writer does the join-row
bookkeeping. Two details cover the wire format: values arriving from the
browser are strings, so each id is cast through the *target* model's
primary-key type; and the blank entry Rails' hidden-input convention adds to
a multi-select submission is dropped. Without the cast, the signal would
hold `"3"` against the `3` hydration copied in, and `dirty?` would report
the form dirty forever.

A hand-rolled form that *does* submit its selection still works: the JS
client collects every entry of a `[]`-suffixed field name into an array
under the bare key, so a `<select multiple name="song_ids[]">` or a checkbox
group reaches your action as `data["song_ids"]`, a real array. Duplicate
keys *without* the suffix stay last-wins, which is what Rails' hidden-field
checkbox convention depends on.

## Options

| Option | Effect |
| --- | --- |
| `--skip-search` | No filter input, and no option cap — a cap without search would strand options |
| `--limit=N` | How many options the dropdown offers at once (default 50) |
| `--label=COLUMN` | The target column shown per option. Absent means infer: `name`/`title`/`label`/`email`, then the first string column |
| `--css=NAME` | `daisyui`, `tailwind` or `none` — detected the same way the scaffold detects it. Under `none` there is no styling to collapse the panel, so it renders as an inline list |
| `--phlex` | A Phlex component instead of the ERB partial. Absent means detect from what the scaffold left |

## Notes

- **`touch: true` on the join is the pillar of this design.** Writing a join
  row bumps the owner's `updated_at`, which fires the owner's `after_commit`
  ping — that is how a save in one session reaches every open index and show
  page.
- When the generator created the join model, run `bin/rails db:migrate`
  before using the dropdown. And `app/channels/concerns` is a new autoload
  directory on its first use, so restart the server.
- Scaffolds generated before 0.7.0 predate the `extras:` hash the dropdown's
  locals ride on. The generator threads it through those partials itself and
  says so with a `compat` notice — nothing to do by hand, unless you had
  reshaped the partials, in which case the notice tells you what to pass.
