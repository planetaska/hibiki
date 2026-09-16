---
name: hibiki-rails-forms
description: >-
  Reactive forms for hibiki_rails 0.15.0: `Hibiki::Rails::ReactiveForm` with
  `reactive_attributes`, `reactive_association`, `reactive_nested`, `.from`,
  `hydrate`, `commit` vs `commit!`, `dirty?`, `errors`, `error_for`, `to_h`,
  `hibiki_attributes`, two validation layers, wire-type casting. Also the
  add-on generators over a hibiki:rails scaffold: `hibiki:rails:form`
  (re-derive live checks after adding validators), `hibiki:rails:nested`
  (child fieldsets via `Hibiki::Rails::NestedActions`, path grammar,
  ordering), `hibiki:rails:multiselect` (searchable has_many :through
  picker), `hibiki:rails:upload_field` (Active Storage direct upload,
  `--many`, `--accept`). Load when editing app/forms/*_form.rb,
  wiring inline edit or create in a channel, adding a child fieldset, tag
  picker or upload, or when a save "does nothing", `dirty?` sticks true,
  errors never show, or RecordNotUnique hits the log. Base scaffold and its
  options: load hibiki-rails-scaffold. Channels, islands, `on`, JS client:
  load hibiki-rails.
license: MIT
metadata:
  author: planetaska
  hibiki: "0.3.0"
  hibiki_rails: "0.15.0"
  hibiki_phlex: "0.1.0"
---

# hibiki-rails-forms

Covers hibiki_rails 0.15.0. The family versions table lives in the `hibiki`
skill.

## What a reactive form is

A reactive form holds one ActiveRecord record's attributes as signals. Copy the
record in when the form opens (hydrate), edit and validate through signals
while the user types, and write everything back in one step when the user
saves (commit). The record itself appears only at those two boundaries, which
is what keeps the signal graph free of live records. Every field is an
ordinary `Hibiki::Reactive` state, so deriveds over fields, `transmit_value`
of an error message, and subclass inheritance all work as in the core gem.

## Declaring one

```ruby
class TodoForm
  include Hibiki::Rails::ReactiveForm

  reactive_attributes Todo, :title, :done

  derived(:title_error) { "can't be blank" if title.strip.empty? }
  derived(:valid?)      { title_error.nil? }
end

form = TodoForm.from(Todo.find(id))
form.title = "buy milk"   # a plain signal write
form.dirty?               # => true
form.commit               # => false when the model is invalid
form.error_for(:title)    # => the model's own message after a failed commit
```

Pass the model as a String (`reactive_attributes "Todo", :title`) when the
form lives under `app/`, because the macro resolves the name on every use and
a memoized constant would go stale across a Zeitwerk reload. Pass the
constant only for a form outside `app/`.

## The surface

| Call | What it does |
| --- | --- |
| `.from(record, ...)` | `new(...).hydrate(record)`; the documented constructor. Extra args go to `#initialize`. |
| `#hydrate(record)` | Copies attributes in again inside one `Hibiki.batch`; also the reset. |
| `#record` | The hydrated record, a plain ivar, never a signal. |
| `#persisted?` | Delegates to the record, so a view can label Create or Update. |
| `#to_h` | Declared attributes and values; nested children ride as `<name>_attributes`. |
| `#dirty?` | A derived: `to_h` differs from the snapshot hydration took. |
| `#commit` | `record.update(**to_h)`; false plus mirrored `#errors` on failure, re-hydrates on success. |
| `#commit!` | Same, then re-assigns with `update!` so it raises `ActiveRecord::RecordInvalid`. |
| `#errors` | `{ title: ["can't be blank"] }`, a fresh hash mirrored at the last failed commit. |
| `#error_for(:title)` | First message for one field, or nil. |
| `#to_nested_attributes` | This form's slice of a parent's `*_attributes`, with `id:` and `_destroy:`. |
| `#nested_add(name)` / `#nested_remove(name, child)` / `#nested_move(name, child, to:)` | Replace the child array (signals notify on assignment, not mutation). |
| `#mark_for_destruction` / `#marked_for_destruction?` | AR's spelling; `hydrate` unmarks. |
| `.hibiki_attributes` | The declared scalar names plus any `<singular>_ids`; the allowlist channels check. |
| `.hibiki_model` / `.hibiki_nested` / `.hibiki_nested_form(name)` | Declarations, resolved on every use. |

Wire values arrive as strings, so every generated writer casts through
`Model.type_for_attribute(name).cast(value)` before the signal sees it:
`form.done = "0"` stores `false`, `form.priority = "3"` stores `3`. Skip the
macro and hand-roll states, and `"3"` never equals the `3` hydration copied
in, so `dirty?` sticks true.

## Using it in a channel

Guard every field write with `hibiki_attributes`, because the payload is
untrusted and the declared list is the strong-params analogue. Save with
`commit`, not `commit!`, because an unrescued raise on the graph thread ends
the action with nothing rendered.

```ruby
def set_field(data)
  name = data["field"].to_s.to_sym
  return unless TodoForm.hibiki_attributes.include?(name)

  @form.public_send(:"#{name}=", data[name.to_s])
end

def save(data)
  return unless @editing_id.peek

  assign(@form, data)          # loops hibiki_attributes over the payload
  return unless @form.commit   # false already mirrored the errors

  @editing_id.value = nil
  invalidate
end
```

Wire the submit with `on(:save, event: :submit, reset: false)`, because the
client's default resets a submitted form and a failed commit would blank the
user's values. Build the form once in `build_graph` (`@form = TodoForm.new`)
and `hydrate` it per edit, as the scaffold does, so one graph never
accumulates forms; `from(record)` is just `new.hydrate(record)`, and `commit`
raises "has no record" on a form that was never hydrated.

## Two validation layers

Write deriveds over fields for per-keystroke feedback; they are hand-picked
like client-side validation, because a derived cannot check uniqueness
without a query and must not run one per keystroke. The model's `validates`
stays authoritative: a failed `commit` copies `record.errors` into `#errors`
(mirroring), one round trip later. `error_for` reads both, so
`transmit_value(:title_error) { @form.error_for(:title) }` streams either
kind. Generated forms gate live errors behind `dirty?`, so a fresh create
form is not covered in blank-field messages:

```ruby
derived(:live_errors) do
  { title: ("can't be blank" if title.to_s.strip.empty?) }.compact
end
derived(:valid?) { live_errors.empty? }
def error_for(name) = super || (live_errors[name.to_sym] if dirty?)
```

## Create and update with one form

Use `from(Todo.new)` for create, because it hydrates the column defaults and
`commit` on an unpersisted record INSERTs; `persisted?` flips afterwards
since a successful commit re-hydrates from the saved record (callbacks and DB
defaults may have changed values). `dirty?` on a create form then means
"changed from the defaults", exactly the Create button's condition.

## Nested forms

`reactive_nested :credits, "CreditForm"` declares a signal holding an array
of child forms over an `accepts_nested_attributes_for` association. Include
`Hibiki::Rails::NestedActions` in the channel for the generic actions
`nested_add`, `nested_remove`, `nested_move`, `nested_set_field`. A control
names its node with `path` (association names alternating with child keys,
`c<id>` persisted, `n<seq>` new) and `dom` (which open form):

```
"credits"                        # the collection, nested_add
"credits/c3"                     # a child, nested_remove / nested_move
"credits/c3/contributions/n1"    # a grandchild, nested_set_field
```

Every hop is checked against `hibiki_nested`, the live children and the child
class's `hibiki_attributes`, so a stale or forged path drops silently. Inputs
name themselves `"#{path}/#{field}"` and send `with: { dom:, path:, field: }`.
Override the private `nested_form_for(dom)` on a channel that is not the
scaffold's, because the default resolves `@form`/`@editing_id` and
`@new_form`/`@creating`. One `commit` persists the whole tree, because
`to_h` emits `credits_attributes` hashes with `id:` and `_destroy:`.

Generate an edge per run:

```sh
bin/rails g hibiki:rails:nested Song Credit role:string position:integer
bin/rails g hibiki:rails:nested Credit Contribution part:string
bin/rails db:migrate
```

A `position` column (or `--position=COLUMN`) makes the edge ordered: the
parent's `to_h` fills positions from array order and rows get up/down
controls firing `nested_move` with `to:` as the index among visible siblings.
`--skip-position` opts out. Details in `references/nested-forms.md`.

## Multi-select over has_many :through

`reactive_association :songs` (declared after `reactive_attributes`, or it
raises) adds a `song_ids` signal that hydrates from the record's ids reader
and commits through the association writer. Each id is cast through the
target's primary-key type and blanks are dropped.

```sh
bin/rails g hibiki:rails:multiselect Album Song Track
```

The concern lands at `app/channels/concerns/albums_channel/songs_multiselect.rb`
and adds `toggle_song` and `search_songs` actions; the channel gains one
`include SongsMultiselect`. A toggle is a SET of one box's `checked` state,
not a flip, so two tabs converge. The boxes are deliberately not named
`song_ids[]`, because the graph owns the selection and a filtered submit
would drop hidden picks. `OPTIONS_LIMIT` (`--limit`, default 50) caps the
list; `--skip-search` drops both the input and the cap. `touch: true` on the
join's owner side is what pings other sessions. Details in
`references/multiselect.md`.

## File uploads

```sh
bin/rails g hibiki:rails:upload_field Album cover
bin/rails g hibiki:rails:upload_field Album photos --many --accept=image,pdf
```

The inline form's file input carries no `name`, because a File cannot ride a
JSON channel message; the shared `upload_field_controller.js` direct-uploads
on pick and calls `performOn` with `{ dom, signed_id, filename }`. The
concern keeps that pending pick in `@pending_cover` keyed by form `dom`,
and attaches through a fresh `find_by` only after a successful save. The
classic page form uses `direct_upload: true` and a `remove_cover` virtual
attribute. `--many` appends through `attach` and never assigns the
collection, because assigning a `has_many_attached` replaces it. Details in
`references/file-uploads.md`.

## Re-derive after adding validators

Run `bin/rails g hibiki:rails:form Book` after adding validators, because the
full scaffold runs before its migration and its form starts with no live
checks. It rewrites only the form object and the two form views (or only the
form with `--skip-views`), asking per file before replacing edits. The `form`
notice means `live_errors` came out empty; the `unique` notice names a unique
index with no validator, which otherwise raises `RecordNotUnique` in the
channel instead of showing an error.

## Pitfalls

- `commit!` inside a channel action. The raise on the graph thread ends the action and nothing re-renders; return on a false `commit` instead. (reactive-forms)
- A live derived that checks uniqueness. It needs a query per keystroke; leave uniqueness to the model, which mirrors at commit. (reactive-forms)
- Hand-rolled states holding wire strings. `"3" != 3`, so `dirty?` sticks true; `reactive_attributes` casts through the column type. (reactive-forms)
- Putting the record in a signal. It is the boundary; hold it in an ivar and touch it only in `hydrate`/`commit`. (reactive-forms)
- Committing a form that was never hydrated. `commit` raises "has no record"; use `.from(record)` or `new` followed by `hydrate`. (reactive-forms)
- Passing the model as a constant from under `app/`. The macro memoizes nothing so a String survives reloads; a constant pins the old class. (reactive-forms)
- Mutating `#errors`. Each mirror is a fresh hash so equality gating works; treat it read-only. (reactive-forms)
- Expecting new validators to show live. Live clauses are a generation-time snapshot; re-run `hibiki:rails:form` or write the clause. (crud-notes)
- Wondering why a blank create form shows no errors. Generated `error_for` gates live errors on `dirty?`; mirrored ones always show. (crud-notes)
- A unique index without `validates uniqueness:`. The duplicate raises `RecordNotUnique` in the channel and the busy ack still clears, so the user sees a clean no-op. (crud-notes)
- Assuming `NestedActions` methods are internal. Every public method is a client-invocable action by design; keep helpers private. (nested-forms)
- Sending `to:` as an index over all children. It counts visible siblings only; marked rows sit at the tail and refuse to move. (nested-forms)
- Naming multiselect boxes `song_ids[]`. A filtered submit would drop hidden selections; send `checked` per box to the toggle action. (multiselect)
- Expecting `data["song_ids"]` from a `[]` field to be a string. The client collects `[]`-suffixed names into an array; bare duplicate keys stay last-wins. (multiselect)
- Reading `album.cover` on a channel row. Rows are frozen and `strict_loading`; read `cover_attachment` and preload with `with_attached_cover`. (file-uploads)
- Attaching to the frozen row. Attach through a fresh `find_by` after the save, as the concern does. (file-uploads)
- Assigning `photos: [...]` on a `has_many_attached`. Since Rails 7.1 that replaces the collection; append with `attach`. (file-uploads)
- Forgetting the restart. `app/forms` and `app/channels/concerns` are new autoload roots and raise `NameError` until the server restarts. (crud-notes)
- Omitting `reset: false` on an edit form's submit. A failed commit blanks the fields the user typed. (reactive-forms)

## Reference files

- `references/reactive-forms.md`: the full surface, casting, validation layers, generated form shape.
- `references/nested-forms.md`: `reactive_nested`, `NestedActions` payloads, path grammar, ordering, generator options.
- `references/multiselect.md`: `reactive_association`, the concern's actions and signals, generator options.
- `references/file-uploads.md`: the concern, the Stimulus controller, `--many`, `--accept` tokens, prerequisites.

## Related skills

- `hibiki`: the core signals, `Hibiki::Reactive` macros, and the family router and versions table.
- `hibiki-rails`: channels, islands, `on`, the JS client, ActiveRecord patterns, troubleshooting.
- `hibiki-rails-scaffold`: `hibiki:rails:scaffold` and its options, the generated channel and query object.
- `hibiki-rails-motion`: enter and leave transitions for re-rendered rows and forms.
- `hibiki-phlex`: reactive Phlex components with hibiki_phlex.
