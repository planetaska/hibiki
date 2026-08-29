---
title: Nested forms
nav_order: 3
---

# Nested forms

Consider this scenario: a song has many credits; a credit has many contributions. On a classic Rails
form you edit a tree like this with `accepts_nested_attributes_for` and
`fields_for`: the parent's form embeds a fieldset for the children, one submit
posts everything, and one save persists it all.

Hibiki keeps the one save but moves the editing into the open form. In a
[reactive form]({{ "/reactive-forms/" | relative_url }}), each field of an
edit form is a *signal* — a server-side value the page reacts to, so an edit
travels up the resource's channel (the WebSocket connection the [CRUD
scaffold]({{ "/crud-scaffolding/" | relative_url }}) set up) and the page updates from the new value. A nested form extends this to the children: each
child row becomes a small form object of its own, and the parent form holds
them in an array. Rows are added, edited, reordered and removed while the form
stays open, and the save at the end still persists the whole tree at once.

`hibiki:rails:nested` wires one parent→child edge onto a resource the CRUD
scaffold already generated:

```sh
# Here, Song is a resource generated with Hibiki's scaffold:
# bin/rails g hibiki:rails:scaffold Song title...
#
# Credit and Contribution are regular child models — pass a field list
# and each is created for you (model + migration) when missing:

bin/rails g hibiki:rails:nested Song Credit role:string position:integer
bin/rails g hibiki:rails:nested Credit Contribution part:string
bin/rails db:migrate
```

Each run wires exactly one edge, parent to child. Depth comes from
composition: run the generator once per edge, with no limit on how deep the
tree goes.

When the child model already exists (migrated, with a `belongs_to` to the
parent), the attribute arguments only choose which of its columns appear on
the row, and in what order — the schema stays the source of truth. When the
child model doesn't exist, the field list creates it (since 0.9.1): the model
and its migration come from Rails' own model generator, with
`song:references` prepended for you. Run the migration before using the
fieldset.

The second run above finds that `Credit` is itself a nested child (its
`_credit_fields` partial exists under `app/views`), so it nests the
contributions fieldset inside the credit row, wired to the owning resource's —
the song's — channel and page form. No extra arguments are needed.

## What lands where

For the root edge (`Song Credit`; ERB shown — `--phlex` emits components
instead):

| File | What happens |
| --- | --- |
| `app/forms/credit_form.rb` | **Created.** A [ReactiveForm]({{ "/reactive-forms/" | relative_url }}) over the child's own columns. The parent's foreign key and the position column are deliberately left out — the tree supplies one and the row order supplies the other. |
| `app/views/songs/_credit_fields.html.erb` | **Created.** One child row: its inputs, a remove control, and ↑/↓ controls when the edge is ordered. |
| `app/models/song.rb` | Gains `has_many :credits` (scoped by `order(:position)` when ordered) and `accepts_nested_attributes_for`. |
| `app/forms/song_form.rb` | Gains `reactive_nested :credits, "CreditForm"` — and, when ordered, a `to_h` override that stamps positions from array order. |
| `app/channels/songs_channel.rb` | Gains `include Hibiki::Rails::NestedActions` (once — every later edge shares it) and `includes(...)` preloads on the actions that open forms. |
| `_form.html.erb` (the full-page form) | Gains a classic `fields_for` fieldset — the no-JavaScript path, described [below](#the-degraded-path). |
| The controller | The `credits_attributes` group joins `params.expect`, `_destroy` included. |
| `app/models/credit.rb` + its migration | **Created** when the model doesn't exist — from the field list, with the parent reference prepended. |
| A migration | Only when `--position=COLUMN` names a column an existing table lacks. A created child's columns all ride its own migration. |

## The child forms live in the signal graph

`reactive_nested :credits, "CreditForm"` declares a signal holding an array
of child forms — one `CreditForm` per row. The fieldset's controls don't
submit anything. Each fires a generic channel action from
`Hibiki::Rails::NestedActions` and names the node it means with a `path`:
association names alternating with child keys, to any depth:

```
"credits"                       # the collection      (nested_add)
"credits/c3"                    # a child             (nested_remove, nested_move)
"credits/c3/contributions/n1"   # a grandchild        (nested_set_field)
```

`c3` is a persisted child, keyed by its id; `n1` is a new one. The key is
stable across repaints, so it doubles as the row's DOM identity.

The scaffold can have two forms open at once — a row's edit form and the
inline create form. A `dom` value beside the path names which one the action
aims at, so the two never cross-write. This is the same convention the
[multi-select]({{ "/multiselect/" | relative_url }})'s toggles use.

Every hop in the path is checked on the server: the association name against
the form class's `reactive_nested` declarations, the child key against the
live children, and the field name against the child form's
`reactive_attributes`. A stale or forged path drops the action. Inputs name
themselves `"#{path}/#{field}"`, which keeps each child's change events
unique — and inert in a full-page submit, where only the declared scalars are
assigned.

On a channel that isn't the scaffold's, override the private
`nested_form_for(dom)` — the default resolves the scaffold's
`@form`/`@editing_id` and `@new_form`/`@creating` instance variables.

## One save persists the whole tree

The parent form's `to_h` serializes the tree as nested `credits_attributes`
hashes, each child carrying `id:` when persisted and `_destroy:` when marked
for removal. That is exactly the shape `accepts_nested_attributes_for`
expects, so `commit` hands the whole tree to ActiveRecord and the record's
one save persists everything — the parent's own fields, child edits, inserts,
removals, and order.

A failed commit distributes each child record's errors onto the matching
child form, so "can't be blank" lands on the row that earned it. The
generated child form also waits for `dirty?` before showing its live errors,
so a freshly added row starts clean rather than covered in blank-field
messages.

Removing a persisted child marks it `_destroy`: the row disappears from the
fieldset but still rides along to the save, which deletes it. Removing a new
child just takes it out of the array. Any of these changes makes the parent's
`dirty?` true, and cancel is the undo — closing the form without saving
discards the form's copy of the tree, destroy marks included.

## Ordering

When the child table has a `position` column, the generator detects it and
wires ordering by default. `--position=COLUMN` names a different column,
generating the `add_column` migration when the column is absent;
`--skip-position` opts out. A **created** child is never ordered silently:
put `position` in the field list, or pass `--position=COLUMN`, and the column
joins the child's own migration.

An ordered edge never edits position values directly — **the visual order is
the ordering**. The parent form's `to_h` stamps the column from array order
at save time, and each row gains ↑/↓ controls that fire `nested_move`. The
action's `to:` is the target index among the child's *visible* siblings; the
server clamps it, and rows marked for destruction sit outside the visible
order and refuse to move. The repaint after a move shows the rows in the
order the user asked for.

A drag-and-drop layer fires the same action, once per drop. [Driving an
island from JS]({{ "/driving-an-island/" | relative_url }}) walks through the
full SortableJS example over this exact fieldset.

## The degraded path

The full-page `_form` gains a classic `fields_for` fieldset — index-keyed
names, the `id` pair, a `_destroy` checkbox per persisted row — and the
controller's `params.expect` gains the matching `credits_attributes` group.
With no scripts and no socket, the standard new and edit pages still edit the
whole tree the way Rails always has. This is the same [fallback posture]({{
"/the-js-client/" | relative_url
}}#falling-back-to-native-behavior) the scaffold takes
everywhere else: the reactive form is an enhancement over a page that works
without it.

## Options

| Option | Effect |
| --- | --- |
| `--position=COLUMN` | Order by COLUMN, generating its migration when the column is absent. Default: detect a `position` column. |
| `--skip-position` | Unordered — no scope, no position stamping, no ↑/↓ controls. |
| `--phlex` | Emit a Phlex fields component. Absent means detect from what the scaffold left. |
| `--css=NAME` | `daisyui`, `tailwind` or `none` — detected the same way the scaffold detects it. |

## Notes

- **Run the migration** before using an edge whose child model or
  `--position` column was generated.
- The `NestedActions` include is idempotent: the channel gains it on the
  first edge, and later edges reuse it. Like any concern of public methods,
  everything public on it becomes a client-invocable action — that is its
  job.
- `reactive_nested` and `NestedActions` are ordinary gem API, usable without
  the generator. The generator's output is the reference for the wiring they
  expect.
