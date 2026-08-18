---
title: Nested forms
nav_order: 3
---

# Nested forms

Consider this scenario: a song has many credits; a credit has many contributions. On a classic Rails
form we'd use `accepts_nested_attributes_for` + `fields_for`: one submit and one
save take care of the whole tree. On a reactive resource the same tree lives **in the
graph** — rows are added, edited, reordered and removed over the channel with
the form still open, and one save still persists everything.

`hibiki:rails:nested` wires one parent→child edge onto a resource the
[CRUD scaffold]({{ "/crud-scaffolding/" | relative_url }}) already generated:

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

Each run wires exactly one edge — **depth is composition**, and there's no level limit. With an existing child model (migrated, with a `belongs_to` to the
parent), attribute arguments only reorder or subset the columns the schema
already knows — the facts stay the schema's. When the child model doesn't
exist, the field list creates it (since 0.9.1): model and migration via
Rails' own model generator, with `song:references` prepended for you. Run
the migration before using the fieldset.

The second run finds `Credit` is itself a nested child (its
`_credit_fields` partial exists under `app/views`) and nests the
contributions fieldset inside it, wiring the owning resource's channel and
page form — no extra arguments needed.

## What lands where

For the root edge (`Song Credit`, ERB shown; `--phlex` emits components):

| File | What happens |
| --- | --- |
| `app/forms/credit_form.rb` | **Created.** A [ReactiveForm]({{ "/reactive-forms/" | relative_url }}) over the child's own columns — the parent's foreign key and the position column deliberately absent |
| `app/views/songs/_credit_fields.html.erb` | **Created.** One child row: path-addressed inputs, remove control, ↑/↓ when ordered |
| `app/models/song.rb` | `has_many :credits` (with an `order(:position)` scope when ordered) + `accepts_nested_attributes_for` |
| `app/forms/song_form.rb` | `reactive_nested :credits, "CreditForm"` — and, when ordered, a `to_h` override stamping positions from array order |
| `app/channels/songs_channel.rb` | `include Hibiki::Rails::NestedActions` (once — every later edge shares it) and `includes(...)` preloads on the form-opening actions |
| `_form.html.erb` (the full page form) | A classic `fields_for` fieldset — the degraded path |
| the controller | The `credits_attributes` group in `params.expect`, `_destroy` included |
| `app/models/credit.rb` + its migration | **Created** when the model doesn't exist — from the field list, the parent reference prepended |
| a migration | Only when `--position=COLUMN` names a column an existing table doesn't have — a created child's columns all ride its own migration |

## The array lives in the graph

`reactive_nested :credits, "CreditForm"` declares a signal holding an array
of child forms. The fieldset's controls don't submit anything — each fires a
generic action from `Hibiki::Rails::NestedActions`, addressing its node by
`path`, association names alternating with child keys to any depth:

```
"credits"                       # the collection      (nested_add)
"credits/c3"                    # a child             (nested_remove, nested_move)
"credits/c3/contributions/n1"   # a grandchild        (nested_set_field)
```

`c3` is a persisted child (its id), `n1` a new one — the key is stable across
repaints, so it doubles as the row's DOM identity. A `dom` value beside the
path names which open form the write aims at, exactly like the
[multi-select]({{ "/multiselect/" | relative_url }})'s toggles — a row edit
and the inline create form can be open side by side without cross-writing.

Every hop is gated server-side: the association against the form class's
`reactive_nested` declarations, the key against live children, a field
against the child's `reactive_attributes`. A stale or forged path drops the
action. Inputs name themselves `"#{path}/#{field}"` — per-child unique for
change events, and inert in a submit payload, where only declared scalars are
assigned.

On channels that aren't the scaffold's, override the private
`nested_form_for(dom)` — the default resolves the scaffold's
`@form`/`@editing_id` and `@new_form`/`@creating` ivars.

## One save, whole tree

The parent form's `to_h` serializes the tree as recursive
`credits_attributes` (each child carrying `id:` when persisted and
`_destroy:` when marked), so `commit` hands ActiveRecord exactly what
`accepts_nested_attributes_for` expects and the record's **one save**
persists everything — parent scalars, edits, inserts, removals, order.

A failed commit distributes each child record's errors onto the matching
child form, so "can't be blank" lands on the row that earned it; the
generated child form's live errors additionally wait for `dirty?`, so a
freshly added row starts clean. Removing a persisted child marks it
`_destroy` (it disappears from the fieldset but rides to the save); removing
a new one just leaves the array. `dirty?` is true for any of it, and
cancel is the undo — closing the form without saving discards the graph's
copy, marks included.

## Ordering

A `position` column on the child table is detected and wired by default;
`--position=COLUMN` names a different one (generating the `add_column`
migration when it's absent), `--skip-position` opts out. A **created** child
is never ordered silently — put `position` in the field list, or pass
`--position=COLUMN` and the column joins the child's own migration.

Ordered edges don't edit positions — **the visual order is the ordering**.
The parent form's `to_h` stamps the column from array order at save time,
and the fieldset gets ↑/↓ controls firing `nested_move`, whose `to:` is the
target index among the child's *visible* siblings (clamped server-side —
rows marked for destruction sit out of the visible order and refuse to
move). The repaint after a move arrives in the order the user asked for.

The same action is what a drag-and-drop layer fires once per drop —
[Driving an island from JS]({{ "/driving-an-island/" | relative_url }})
shows the full SortableJS example over this exact fieldset.

## The degraded path

The full-page `_form` gains a classic `fields_for` fieldset: index-keyed
names, the `id` pair, a `_destroy` checkbox per persisted row — and the
controller's `params.expect` gains the matching `credits_attributes` group.
No scripts, no socket: the standard new/edit pages still edit the whole tree
the way Rails always has. This is the same [fallback]({{ "/the-js-client/" |
relative_url }}#fallbacks-the-native-behavior-as-the-degraded-path) posture
the scaffold takes everywhere else.

## Options

| Option | Effect |
| --- | --- |
| `--position=COLUMN` | Order by COLUMN, generating its migration when absent. Default: detect a `position` column |
| `--skip-position` | Unordered — no scope, no stamp, no ↑/↓ |
| `--phlex` | A Phlex fields component. Absent means detect from what the scaffold left |
| `--css=NAME` | `daisyui`, `tailwind` or `none` — detected like the scaffold's |

## Notes

- **Run the migration** before using an edge whose child model or
  `--position` column was generated.
- The `NestedActions` include is idempotent — the channel gains it on the
  first edge and later edges reuse it. Like any concern of public methods,
  everything public on it is a client-invocable action; that is its job.
- `reactive_nested` and `NestedActions` are ordinary gem API, usable without
  the generator — the generator's output is the reference for the wiring
  they expect.
