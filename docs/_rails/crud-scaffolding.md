---
title: CRUD scaffolding
nav_order: 4
---

# CRUD scaffolding

`rails g scaffold` gives you a resource that works by reloading the page. The
scaffold generators here give you the same resource, live: search, filtering,
sorting and pagination are signal state rather than page loads, rows edit in
place, and a write from anywhere — another tab, another user, the plain
controller, a console — repaints every open list.

Everything is derived from the model's schema (columns, types, `belongs_to`
reflections, validators) or from the same `NAME field:type` argument list Rails'
own scaffold takes.

## Before you run it

The generated views are stamped through `Hibiki::Rails::Helpers` and driven by
the gem's packaged Stimulus controller, so the one-time install has to have
happened first:

```sh
bin/rails g hibiki:rails:install
```

That registers the client, includes the helpers, and writes the `ApplicationCable`
boilerplate a stock app doesn't have until its first `rails g channel`. See
[Quick start]({{ "/rails-quick-start/" | relative_url }}) if you haven't done it.

## The two commands

```sh
# Full scaffold, this creates:
# Model, migration, fixtures, route, and the reactive resource
bin/rails g hibiki:rails:scaffold Book title:string available:boolean author:references
bin/rails db:migrate

# For existing model, use scaffold_controller:
# The schema is automatically read for you
bin/rails g hibiki:rails:scaffold_controller Book
```

`hibiki:rails:scaffold` subclasses Rails' own resource generator, so the model,
its migration, its fixtures and the route all come from Rails, unchanged. Only
the controller half is replaced. It **requires at least one field**: the
migration has not run by the time the views are generated, so there is no schema
to read yet and the argument list is the only source of truth. For an existing
model, use `scaffold_controller`.

`hibiki:rails:scaffold_controller` is the overlay. It is separately invokable on
purpose, and re-running it is a normal thing to do — after adding validators, or
a column, or when you want a different field order.

Namespaced names work (`admin/book`), as they do for the [component-shape
generators]({{ "/generators/" | relative_url }}).

## What the scaffold writes

Per resource, with `Book` as the example:

| File | What it is |
| --- | --- |
| `app/channels/books_channel.rb` | The list island's graph: a `db_version` token, the search/filter/sort/page signals, the `rows`/`counts`/`remaining` deriveds, one render effect, and the client-invocable actions |
| `app/channels/book_channel.rb` | The show page's graph — one live record |
| `app/models/book_query.rb` | The query, in one place, plus `PAGE_SIZE` and the `SEARCHABLE`/`FILTERABLE`/`SORTABLE` allowlists |
| `app/models/book_row.rb` | A `Data` projection: one plain value per row, so the graph never holds a live record |
| `app/forms/book_form.rb` | A [reactive form]({{ "/reactive-forms/" | relative_url }}) over the model's attributes |
| `app/controllers/books_controller.rb` | Scaffold-shaped; still serves the first paint and the non-JS path |
| `app/views/books/*` | `index`/`show`/`new`/`edit` plus `_list`, `_book`, `_book_form`, `_form`, `_controls`, `_pagination`, `_field_error`, `_busy` |

Two of those are worth knowing about before you read the code.

**`book_row.rb` exists because `ActiveRecord#==` compares class and id only.** A
reloaded record is `==` to the stale one it replaces, so re-assigning a signal
from a fresh query would be a silent no-op — hibiki treats an equal write as
nothing happened. The projection is a `Data`, whose structural `==` is what lets
the rows derived notice a change at all. It carries every attribute except the
timestamps, plus one label per `belongs_to`, so the row partial never walks an
association off the graph thread.

**`book_query.rb` is not optional once a page size exists.** The controller's
first paint and the channel's `rows` derived must apply the same window, and a
hand-copied scope in the controller is where that drifts. It lives in
`app/models` rather than a tidier `app/queries` because Rails computes autoload
paths from the `app/*` glob at boot — see the restart notice below.

## Options

| Option | Effect |
| --- | --- |
| `--css=NAME` | Markup variant for **every** generated view: `daisyui`, `tailwind` or `none`. Absent means detect — DaisyUI, then Tailwind, then stock. |
| `--infinite-scroll` | Grow the page on scroll instead of standard pagination |
| `--skip-pagination` | Skips pagination altogether |
| `--skip-search` | Omit the search box and the `LIKE` terms behind it |
| `--page-size=N` | Rows per page (default 20) |
| `--skip-routes` | Don't touch `config/routes.rb` |

`--css=none` means no *styling* class. The `hbk-*` hooks the loading state needs
are structural, not decorative, and stay in every variant.

`--skip-pagination` is worth a note because it shows how the generated code is
meant to be edited: it emits `PAGE_SIZE = nil` rather than a template
conditional. `.limit(nil)` and `.offset(nil)` are both relation no-ops, so the
page count is permanently 1, `remaining` is permanently 0, no page control
renders, and `#go_to_page` short-circuits on its first guard. One constant
instead of `<% if paginated? %>` branching across five files. If you later want
pages back, set the constant.

## Field order decides generated form fields order

With no field list, the columns follow whatever `columns_hash` reports — which,
for an app built from `schema.rb`, is alphabetical. A generated form can end up
reading "Available, Intro, Title" where a person would have led with the title.
There is no authored order to recover from a schema, so the argument list is the only clue:

```sh
bin/rails g hibiki:rails:scaffold_controller Book title:string intro:text available:boolean
```

A field the model has no column for is still generated, from the argument list
alone, and named in the post-install output. It may be a column whose migration
is still to come, and a silently missing field is the worse failure — but nothing
about it was read from the model, so it carries no validator, no bound and no
association label.

## Injection notice for pre-existing models

This is the part that separates it from `rails g scaffold`, and the part to know
before you run it against an app you care about. **Three files you already own
are modified.** All three edits are idempotent, all are announced in the output,
and all leave anything you already declared alone.

**The model being scaffolded** gains one `delegate` per `belongs_to` and the
`after_commit` broadcast the whole thing hangs off. The delegate is not
cosmetic: the row partial prints the association's label, and the show page hands
that same partial a live record, so without it the show page raises on arrival.

**Every model a `belongs_to` points at** gains two things (which Rails' own
`author:references` never writes):

- the **`has_many` half** — without it, the destroy button this generator emitted
  raises `ActiveRecord::InvalidForeignKey`;
- **a broadcast ping of its own**, because a row prints the parent's *label* rather than its
  id. Rename an author and every open books index would otherwise keep showing
  the old name.

**`config/routes.rb`** gains `resources :books`, unless `--skip-routes`.

Two behaviours in there are worth stating (rather than leaving you to discover):

### `dependent:` follows the association, not the column

- Required association → `dependent: :destroy`.
- `optional: true` →`dependent: :nullify`.

Column nullability is the wrong signal: `belongs_to_required_by_default` means a
nullable foreign key routinely backs a required association, and `:nullify` there
leaves rows that fail their own validations. This is a line you own — change it
and re-running the generator will leave your choice alone.

### The broadcast ping is collection-grained

Reaching each child's own member streamable (e.g broadcasting Author name change for all books related to that author) would mean loading every child inside
the callback, unbounded, on every parent write. So the ping goes to the
collection. The consequence: renaming a parent (the Author)
repaints every open **index**, but an open child (the author's Book) **show** page keeps the stale
label (author's name) until reload. The injected comment explains this - because otherwise it looks like a bug.

## Live validation is limited to what a form can check

Per-field errors appear as you type, and they are derived from the model — but
only from the rules a form can actually evaluate before a round trip: presence,
length, and numericality bounds that carry no `allow_nil:`/`allow_blank:`
exemption for the value in hand.

A validator gated on `if:`, `unless:` or `on:` depends on the record rather than
the field, so it contributes **nothing live**. It still runs at commit, still
lands in `#errors`, and the same per-field slots mirror it there with no change
at all — so nothing is lost.

**The clauses are generated once**, into a file the generator then stops owning.
Add validators to the model and re-run `scaffold_controller` to derive them
again, or write them into the form by hand. What re-runs cannot do is find rules
that don't exist yet: it is the check *before* the round trip that has to be
re-derived, never the one after.

## Read the post-install output

Every notice the generator prints exists because the thing it warns about fails
**silently** — nothing raises, and nothing shows up in the file list.

### `restart` — the server afterwards

`app/forms/` is almost certainly new, and **Rails computes autoload paths from
the `app/*` glob at boot**. Until you restart, the new constants raise
`NameError`. This is also why the query object lives in `app/models` rather than
a tidier `app/queries`.

### `css` — rebuild your stylesheet

These views introduce classes your stylesheet has never seen, and Tailwind purges
what it cannot find.

### `assoc` — the display label is a guess

The generator picks the association's first string column. If that is wrong, edit
`app/models/book_row.rb` and the form views.

### `order` — you can choose the field order

Printed when the order came from the schema and there are more than two columns,
with the command that would pick it. See "Field order decides generated form fields order", above.

### `fields` — a field with no column behind it

An explicit field the model has no column for. Check the spelling, or migrate
first and re-run.

### `form` — `live_errors` is thin

The model declares no validators this generator can use before a round trip. The
notice names which of the three reasons applies.

### `unique` — a unique index with no validator

**A database constraint is not a validator**, and the generated form can only
mirror what the model checks. Without a matching `validates … uniqueness:`, a
duplicate raises `ActiveRecord::RecordNotUnique` on the graph thread instead of
showing a field error — which on the graph thread is a line in the development
log, and since the ack clears the busy indicator from an `ensure`, the user sees
a round trip that completes cleanly and saves nothing.

The notice names the column and the exact line to add, for single and composite
indexes alike. The generator deliberately does not write it for you: a uniqueness
validator costs a query on every save, and whether to pay that is your call.

### `skip` — a column the generator left out

With the reason.

### `hint` — the client isn't wired

`hibiki:rails:install` hasn't run, or has been partly undone. Nothing on the
generated page will be live until it does.

## Loading and connection state

Every reactivity in this stack is server-side, so every interaction is a round trip.
The client stamps what it knows about that trip on the island root and on the
control that fired it; the generated app turns those attributes into something a
user can see.

**The mechanism is documented on [the JS client page]({{ "/the-js-client/"
| relative_url }})** — the states, the attributes, the reserved payload key and
the timing knobs. What follows is only what the generator does with it.

`app/views/books/_busy.html.erb` is the app's half of the contract: a small
`<style>` block, rendered once per page and deliberately outside the island, that
maps the client's attributes onto five sites.

| Site | What you see |
| --- | --- |
| The counts line in `_controls` | A small spinner beside the sentence. This partial is never re-rendered, which makes it the safest home for an island-level indicator. |
| Above the list | A non-blocking progress bar. The site that needs one most: the page links are real anchors that jump to the list, so by the time a reply lands the reader is already staring at the *old* list, scrolled to the top of it. |
| The infinite-scroll sentinel | The Load-more control *is* the spinner — it already carries the busy attribute, so this costs no markup. |
| Each row's destroy button | Dimmed while its own trip is in flight. |
| The inline-edit Save button | A spinner in the button. |

Three things about that file are worth knowing.

**It is app code, not gem code.** Rewrite it, restyle it, delete sites you don't
want. Nothing in the gem reads it.

**It is an inline `<style>`** — no build step, and no guess about which asset
pipeline your app uses. If you turn on a Content-Security-Policy that forbids
inline styles, move it into `app/assets/stylesheets`.

**No generated view gained an `if loading` branch**, and that is deliberate.
During a round trip the list on screen is *stale*, not absent — the
server-rendered first paint is real content, and every later update swaps valid
content for newer valid content. So the idiom is to annotate the stale thing, not
to replace it with a skeleton.

Two smaller choices you may want to keep if you rewrite it: buttons and links are
**dimmed, never disabled** (toggling `disabled` mid-gesture drops keyboard focus),
and text inputs are deliberately left alone (a debounced search fires while the
user is still typing, and dimming the field they are typing into reads as a
fault).

## Sorting, and where empty values land

The generated sort is `order(column => direction)` with no `NULLS` clause, and
**that means rows with an empty value land at opposite ends on different
adapters**: SQLite sorts `NULL` first ascending and last descending; PostgreSQL
does the opposite.

This is not a defect and it is not portably fixable. `NULLS LAST` needs SQLite
3.30 or newer, and MySQL has no such syntax at all. If your app targets one
adapter and you want a specific answer, say so explicitly in `book_query.rb` —
the generated code carries a comment at that line for whoever meets it there.

## What to do next

The generated app is a **starting point**. Every file it writes
is ordinary Rails code with no gem-side magic reading it back, and the generator
stops owning a file the moment it writes it. Reshape it as needed.

The most common next steps:

- **Add validators, then re-run `scaffold_controller`** to derive the live
  clauses from them.
- **Reorder or drop fields** in the views.
- **Restart server after the first run**.

And to understand what you were handed:

- [The JS client]({{ "/the-js-client/" | relative_url }}) — the island, the
  helpers, the events, and the loading/connection attributes.
- [Reactive values]({{ "/reactive-values/" | relative_url }}) — the counts
  sentence and the sort label, which live outside the replaced fragment.
- [Reactive forms]({{ "/reactive-forms/" | relative_url }}) — what
  `app/forms/book_form.rb` is.
- [Working with ActiveRecord]({{ "/working-with-active-record/" | relative_url }})
  — the version-signal pattern the channel is built on, and the `after_commit`
  bridge the model injection writes for you.
- [Broadcast helpers]({{ "/broadcast-helpers/" | relative_url }}) — why the list
  is morphed rather than replaced, and what a channel-rendered partial can and
  cannot read.
