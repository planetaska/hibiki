---
name: hibiki-rails-scaffold
description: >-
  hibiki_rails 0.15.0 generators: `hibiki:rails:install`, `hibiki:rails:scaffold Model field:type ...`, `hibiki:rails:scaffold_controller Model`, and the component shapes `stimulus`, `island`, `phlex`. Every option (`--css=daisyui|tailwind|none`, `--infinite-scroll`, the `--skip-*` flags, `--page-size=N`, `--phlex`, `--skip-routes`), what a scaffold writes (channels, controller, ReactiveForm, `app/queries/book_query.rb`, ERB or Phlex views, busy and motion CSS), what it modifies (model after_commit ping, parent has_many, routes, application.js), the post-install notices (restart, css, assoc, order, fields, form, unique, skip, hint, motion), address-bar mirroring, no-JS fallbacks. Load when generating or reshaping a live CRUD resource, on "NameError after scaffold" / "uninitialized constant BookQuery", or when choosing `--phlex` vs hibiki_phlex. Add-on generators (form, nested, multiselect, upload_field) are in hibiki-rails-forms; `hbk-*` motion in hibiki-rails-motion; channels and JS client in hibiki-rails.
license: MIT
metadata:
  author: planetaska
  hibiki: "0.3.0"
  hibiki_rails: "0.15.0"
  hibiki_phlex: "0.1.0"
---

# hibiki-rails-scaffold

Generators shipped with hibiki_rails 0.15.0 (the versions table for the whole
family lives in the `hibiki` skill). This skill covers `rails g hibiki:rails:*`
end to end: what each command writes, what it changes in files you own, and
what the output means when it surprises you.

## What you get

`hibiki:rails:scaffold` is `rails g scaffold` with a live index: search, filter,
sort and paging update the list in place; rows are created and edited inline on
the index page; a write from anywhere (console, job, another tab, the plain
controller) updates every open index. The page still works with the socket
down or with no JavaScript, because every control is real markup (links, a
`button_to` form, one GET form) and the Rails controller answers every request.

The state lives on the server as signals inside an ActionCable channel, one
graph per subscription (one browser tab). A derived `rows` runs the query; one
effect renders the list and sends the HTML down. Read the generated files: they
are ordinary Ruby the generator stops owning the moment it writes them.

## Install prerequisite

Add `gem "hibiki"` and `gem "hibiki_rails"` to the Gemfile, then run
`bin/rails g hibiki:rails:install`. It writes the
`app/javascript/controllers/hibiki_controller.js` shim, appends the register
lines to `controllers/index.js` on jsbundling apps, adds
`include Hibiki::Rails::Helpers` to `ApplicationHelper`, and creates the
`ApplicationCable` channel and connection files when missing. Importmap apps
are done there; bundler apps also `npm add hibiki-rails` pinned to the gem
version, since the two release in lockstep. Every step is idempotent by content
check, so re-running is safe.

The `stimulus` shape works without the install; `island`, `phlex` and both
scaffold commands need it and print a `hint` notice when it is missing, because
an unwired island renders inert with no error anywhere.
Digest in `references/rails-quick-start.md`; the full install story is in the
`hibiki-rails` skill.

## The two commands

```sh
# New resource: model, migration, fixtures and route from Rails itself, then the live resource
bin/rails g hibiki:rails:scaffold Book title:string available:boolean author:references
bin/rails db:migrate

# Existing model: columns, types, belongs_to reflections and validators are read from it
bin/rails g hibiki:rails:scaffold_controller Book
```

Then restart the server if it is running, because `app/forms/` and
`app/queries/` are new directories and Rails computes autoload paths at boot;
until then the new constants raise `NameError`. Read the output next: three
files you already own are modified and every edit is announced.

The full scaffold requires at least one field and raises a generator error
without one, since it runs before its own migration and cannot read a schema.
`scaffold_controller` without fields reads the schema; pass `field:type` pairs
to choose the order or to run before the table is migrated. Namespaced names
(`admin/book`) work in both.

## Options

Both scaffold commands take the same options except the last row.

| Option | Effect |
| --- | --- |
| `--css=NAME` (`daisyui`, `tailwind`, `none`) | Class-name variant for every view. Absent means detect: daisyUI (`"daisyui"` in package.json or `@plugin "daisyui"` in a stylesheet), then Tailwind (`"tailwindcss"` in package.json or `tailwindcss-rails` in the Gemfile), then `none` |
| `--infinite-scroll` | Grow the window on scroll instead of numbering pages |
| `--skip-pagination` | No windowing at all; emits `PAGE_SIZE = nil` |
| `--skip-search` | Omit the search box and the `LIKE` terms behind it |
| `--skip-create` | Omit the inline create form, so New always navigates to `/books/new` |
| `--skip-motion` | No `hibiki_motion.css`, no import, no `data-motion` marks |
| `--page-size=N` | Rows per page, default 20 |
| `--phlex` | Phlex components under `app/views/books/*.rb` instead of ERB |
| `--skip-routes` | `scaffold_controller` only; the full scaffold takes Rails' own `--skip-resource-route` |

## What it writes

| File | What it is |
| --- | --- |
| `app/channels/books_channel.rb` | `BooksChannel`: the index graph, seeded from subscribe params; the actions the client can invoke |
| `app/channels/book_channel.rb` | `BookChannel`: the show page, one frozen record, rejects an unknown `record_id` before building a graph |
| `app/queries/book_query.rb` | `BookQuery`: allowlists, `PAGE_SIZE`, the URL half (`from_params` in, `url_params` out); shared by controller and channel |
| `app/forms/book_form.rb` | `BookForm`, a `Hibiki::Rails::ReactiveForm` with `reactive_attributes` and a `live_errors` derived |
| `app/controllers/books_controller.rb` | Scaffold-shaped; `index` builds `@book_query = BookQuery.from_params(params)` |
| `app/views/books/*` | ERB: `index`, `show`, `new`, `edit`, `_form`, `_list`, `_controls`, `_book`, `_book_form`. Phlex: `index`, `show`, `new`, `edit`, `form`, `list`, `controls`, `row`, `row_form` |
| `app/views/shared/*` | `_pagination` (unless infinite), `_field_error`, `_form_errors` (Phlex: `pagination.rb`, `field_error.rb`, `form_errors.rb`); once per app |
| `app/assets/stylesheets/hibiki_busy.css` | Loading and connection styles keyed on the client's attributes; once per app |
| `app/assets/stylesheets/hibiki_motion.css` | The slide transitions as Tailwind utilities; once per app, never under `--css=none` |

## What it modifies

Three owned files, each edit idempotent and announced, each leaving existing
declarations alone:

- `app/models/book.rb` gains an `after_commit` that broadcasts
  `BooksChannel::CHANGED` and `BookChannel.changed(id)`; without it a write
  from outside the tab never reaches an open index.
- Every model a `belongs_to` points at (`app/models/author.rb`) gains the
  `has_many :books` half, because the generated Destroy button would otherwise
  raise `ActiveRecord::InvalidForeignKey`, and its own `after_commit` ping,
  because rows print `author.name`, not `author_id`. `dependent:` follows the
  `belongs_to` declaration (`:destroy` when required, `:nullify` under
  `optional: true`), not the column's nullability, since
  `belongs_to_required_by_default` makes the two disagree.
- `config/routes.rb` gains `resources :books` unless `--skip-routes`.
- `app/javascript/application.js` gains `import "hibiki-rails/motion"` (the
  `motion` notice reports it) unless motion is off.

## The generated channel at a glance

```ruby
class BooksChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel
  CHANGED = "books:changed"          # the streamable the model pings

  def build_graph
    @db_version = Hibiki::State.new(0)
    @query = Hibiki::State.new(params[:query].to_s)  # subscribe params, normalized
    @filters = Hibiki::State.new(BookQuery.filters_from(params))
    # @sort, @direction, @page, @editing_id, @form, @creating, @new_form ...
    @rows = Hibiki::Derived.new(equals: Hibiki::Rails.record_equals) do
      @db_version.value                 # the tracked dependency
      BookQuery.new(query: @query.value, filters: @filters.value, ...).rows
    end
    Hibiki::Effect.new { broadcast_morph target: "books", partial: "books/list", locals: list_locals }
    transmit_value(:books_matched) { @counts.value[:matched] }
    transmit_url { urls.books_path(**query_url_params) }
  end
end
```

Signals: `@db_version`, `@query`, `@filters`, `@sort`, `@direction`, `@page`,
`@editing_id`, `@form`, and with inline create `@creating`, `@new_form`.
Deriveds: `@counts`, `@page_count`, `@window` (clamps an overshooting page),
`@rows` with `record_equals`, `@remaining`, one `@<parent>_options` per
`belongs_to`. Effects: one `broadcast_morph` of the list (morph, so an open
inline form keeps focus), `transmit_value` for `books_total`, `books_matched`,
`books_range`, `books_direction` and one per primary boolean, and one
`transmit_url`. Actions: `search`, `go_to_page`, `set_filter`, `set_sort`,
`toggle_direction`, `set_<boolean>`, `destroy`, `edit`, `cancel`, `set_field`,
`save`, plus `new_form`, `cancel_new`, `set_new_field`, `create`. Every public
method is an action, so helpers (`subscribed`, `invalidate`, `reset_window`,
`list_locals`, `assign`) stay private. `subscribed` calls `super` and hops
`stream_from CHANGED` into the graph with `graph_actor&.post { Hibiki.batch { ... } }`,
because the callback arrives on a cable thread.

`BookChannel` (show page) mirrors it in miniature: `@row` derived with
`record_equals` over a `strict_loading` frozen `find_by`, one `broadcast_morph`
of `book_<id>`, and `self.changed(id)` = `"book:<id>:changed"`.

## The query object

`BookQuery` exists so the controller's initial render and the channel's `rows`
apply the same window; a scope copied into the controller is where the two
drift apart. Constants: `SEARCHABLE`, `FILTERABLE`, `SORTABLE`,
`DEFAULT_SORT = :id`, `PAGE_SIZE` (nil = no window), `PAGE_WINDOW = 7` for the
numbered control. Class methods: `window`, `page_count`, `page_numbers`,
`range_label`, `direction_label`, `from_params`, `filters_from`, `sort_from`,
`direction_from`, `page_from`, `url_params` (defaults omitted). Instance:
`rows`, `counts`, `page_count`, `remaining`, `url_params`.

`rows` come back `strict_loading`, `readonly!` and frozen, because
`ActiveRecord::Base#==` is class-and-id only and would call an edited row
unchanged; the comparator catches that, and freezing makes the mistakes a
comparison cannot catch raise instead of going stale. Sorting is
`order(column => direction)` plus an `id` tiebreaker with no `NULLS` clause,
since adapters disagree and the syntax is not portable.

## Address bar and no-JS fallbacks

The channel mirrors search, filter, sort and page into the bar through
`transmit_url` (`replaceState`, so Back behaves), and an open inline form
mirrors `/books/7/edit` or `/books/new`. The index view seeds the graph with
`hibiki_island(BooksChannel, cid:, params: @book_query.url_params.presence)`,
so a reload of `/books?query=ruby&page=2` starts the graph where the page
left off; the channel runs those params through the same allowlist
normalizers as the controller, because subscribe params are client input.

Every control is real markup with `fallback: true`: New and Edit have hrefs,
Destroy is a `button_to` DELETE form, the controls form is one GET with
`reset: false` (a reset would blank the search just typed), page links carry
`?page=N`. The infinite-scroll control is two elements on purpose: the wrapper
is the `visible` sentinel and never carries `fallback:` (a sentinel that
navigates on a dead socket would make scrolling navigate), while the Load-more
link inside it has the href and `fallback: true`. Channel-rendered fragments
have no session, so the client freshens the CSRF token from the meta tag
before any native submit.

## Post-install notices

Every notice exists because the thing it warns about fails silently.

| Tag | Meaning | Do |
| --- | --- | --- |
| `restart` | `app/forms`, `app/queries` (or another `app/*`) is new | Restart the server |
| `css` | New class names, or the stylesheet was created but nothing links it | Rebuild Tailwind; add the link line if asked |
| `assoc` | Display label guessed as the parent's first string column | Edit the views if wrong |
| `order` | Fields follow schema (alphabetical) order | Re-run with the fields listed |
| `fields` | A named field has no column | Check spelling, or migrate and re-run |
| `form` | `live_errors` is empty (no validators, no model, or unmigrated) | Add validators, migrate, `bin/rails g hibiki:rails:form Book` |
| `unique` | Unique index with no uniqueness validator; a duplicate raises `RecordNotUnique` in the channel | Add the printed `validates` line |
| `skip` | A column with no form shape (rich text, password digest, polymorphic) | Hand-write the field if needed |
| `hint` | The client is not wired | `bin/rails g hibiki:rails:install` |
| `motion` | `application.js` now imports `hibiki-rails/motion`, or was not found | Add the import to your entry point |
| `stale` / `views` / `warn` | Pre-0.13 query in `app/models`; leftover ERB or shared views; `--phlex` without phlex-rails or `phlex:install` | Delete the old file; install what is missing |

## Component-shape generators

For one small component rather than a resource:

```sh
bin/rails g hibiki:rails:stimulus counter [view_path]  # channel + ChannelController subclass + 2 partials
bin/rails g hibiki:rails:island counter [view_path]    # channel + 2 partials, no per-component JS
bin/rails g hibiki:rails:phlex counter                 # channel + Components::Counter + CounterIsland
```

Each emits one state, one derived, one action, one effect. Render with
`<%= render "counter/counter" %>` (or `render Components::CounterIsland.new`).
`stimulus` and `island` broadcast over Turbo Streams and need a
`turbo_stream_from` line; `phlex` transmits over the subscription and needs
none (the two routes and the first-update trap are in the `hibiki-rails`
skill). Details in `references/generators.md`.

## Add-on generators

Four more build on a scaffolded resource; each writes what it adds and leaves
the rest alone. They belong to the `hibiki-rails-forms` skill; the commands:

- `bin/rails g hibiki:rails:form Book` re-derives the form and the two form
  views after validators change (`--skip-views` for the form only).
- `bin/rails g hibiki:rails:nested Song Credit role:string` nests a child
  collection as a live `fields_for`.
- `bin/rails g hibiki:rails:multiselect Album Song Track` adds a searchable
  dropdown over a `has_many :through`.
- `bin/rails g hibiki:rails:upload_field Album cover [--many] [--accept=image,pdf]`
  adds an Active Storage attachment.

## Pitfalls

- `NameError` for `BookQuery` or `BookForm` right after scaffolding. Rails computes autoload paths at boot and `app/queries`, `app/forms` are new. Restart. (crud-notes)
- Re-running against an app you built. The three owned-file edits are idempotent and announced, but `--force` overwrites generated files without asking. (crud-notes)
- The generated form has no live checks. The full scaffold runs before its migration, and the clauses are a snapshot; after adding validators run `hibiki:rails:form Book`. (crud-notes)
- Fields come out alphabetical. Without an argument list the order is `columns_hash` order; name the fields to choose it. (crud-notes)
- `--phlex` is not hibiki_phlex. The scaffold's Phlex views are stateless `Views::` components with the channel owning state; it needs `phlex-rails` and `bin/rails g phlex:install` or every page raises `NameError`. The hibiki_phlex idiom (component owns state) is the `hibiki-phlex` skill. (crud-notes)
- `--css=none` never writes motion. The transitions are Tailwind utilities, so its output equals `--skip-motion`. (crud-scaffolding)
- Toggling pagination later is one constant. `PAGE_SIZE = nil` turns it off because `.limit(nil)` and `.offset(nil)` are no-ops. (crud-notes)
- Dropping the island's `params:` resets every reload to page 1. The controller reads the URL but the graph's first render replaces it with the defaults. (crud-notes)
- A parent's ping refreshes indexes, not show pages. Reaching each show page would load every child inside the callback, so a stale author name on `/books/7` is by design. (crud-notes)
- Frozen rows raise on a lazy association. `strict_loading` is deliberate; add the preload to `window_scope` instead of unfreezing. (crud-notes)
- A pre-0.13 `app/models/book_query.rb` loads ahead of `app/queries`. Delete it when the `stale` notice names it. (crud-notes)
- Empty values sort to opposite ends on SQLite and PostgreSQL. No `NULLS` clause is emitted; pin it in `book_query.rb` per adapter. (crud-notes)
- Phlex views raise on non-string values, drop `false` attributes and emit no whitespace. The generated components call `to_s`, write `data-turbo` as `"false"` and space siblings explicitly; keep that when editing. (crud-notes)
- Bulk writes never ping. `update_all`, `insert_all`, `update_column` and raw SQL skip `after_commit`; call `invalidate` from the action or bump `@db_version` yourself. (working-with-active-record)
- Four graph rules with their Rails cost: mutating a record in a signal is not a write (nothing re-renders); an equal write sends zero bytes; `rows` is lazy and runs only when read by the effect; only the graph thread may touch signals, which is why `subscribed` hops through `graph_actor`. (crud-notes)
- Broadcast fragments need `turbo_stream_from` and lose the first update without `streamConnected`; the generated index carries the line for you. (the-js-client)

## Reference files

- `references/crud-scaffolding.md`: the commands, the options table, what is written, the add-on commands.
- `references/crud-notes.md`: owned-file edits, frozen rows, fallback paths, the full notices table, the Phlex naming table.
- `references/generators.md`: the three component shapes, arguments, files, render lines.
- `references/rails-quick-start.md`: install and first component, scaffold-angled.

## Related skills

- `hibiki`: the signal core (State, Derived, Effect, batch) and the family router.
- `hibiki-rails`: channels, islands, the JS client, broadcast helpers, ActiveRecord patterns, troubleshooting.
- `hibiki-rails-forms`: ReactiveForm and the form, nested, multiselect, upload_field generators.
- `hibiki-rails-motion`: `data-motion`, the `hbk-*` utilities and `hibiki_motion.css`.
- `hibiki-phlex`: reactive Phlex components with hibiki_phlex, and the `--phlex` contrast.
