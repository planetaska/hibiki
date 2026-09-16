# CRUD notes (digest)

## Files you already own that get modified

Scaffolding `Book` with `author:references` edits three files. Every edit is
idempotent, announced, and leaves existing declarations alone.

| File | Gains | Why |
| --- | --- | --- |
| `app/models/book.rb` | `after_commit` broadcasting `BooksChannel::CHANGED` and `BookChannel.changed(id)` | Signals only notice their own writes; the ping is how console, job and other-tab writes reach an open index |
| `app/models/author.rb` | `has_many :books, dependent: ...` plus its own ping to `BooksChannel::CHANGED` | Destroy raises `ActiveRecord::InvalidForeignKey` without the `has_many`; rows print `author.name`, so a rename must refresh the index |
| `config/routes.rb` | `resources :books` | Unless `--skip-routes` |

`dependent:` follows the `belongs_to` declaration (`:destroy` when required,
`:nullify` under `optional: true`), not the column, which routinely allows
NULL under a required association. The parent's ping refreshes indexes, not
show pages: reaching each show stream would load every book in the callback.

## Why rows are frozen, and the query is one file

`ActiveRecord::Base#==` is class-and-id only, so an edited row re-queried
equals the stale one and hibiki would skip the re-render. `rows` (and the show
channel's `row`) use `equals: Hibiki::Rails.record_equals`; the query freezes:

```ruby
def rows   # FrozenError on write, ReadOnlyRecord on save, strict_loading on a lazy walk
  @rows ||= window_scope.strict_loading.map { it.readonly!; it.freeze }
end
```

The controller's initial render and the channel's `rows` must apply the same
window, and a hand-copied scope drifts; both call `BookQuery`. `PAGE_SIZE` is
the pagination switch: a number is rows per page, `nil` is off, because
`.limit(nil)` and `.offset(nil)` are relation no-ops.

## The address bar and the no-JS paths

`transmit_url` mirrors search, filter, sort and page with `replaceState`; an
open inline form mirrors `/books/7/edit` or `/books/new`. The controller
renders from `BookQuery.from_params(params)` and the island subscribes with
`params: @book_query.url_params.presence`, so the graph starts where the page
was; drop the params and the first render resets to page 1. Subscribe params
are untrusted: they pass through `filters_from`, `sort_from` and friends.

- New and Edit links carry real hrefs with `fallback: true`.
- The controls form is one GET with `reset: false`; a reset would blank the
  query just typed. Under `--skip-search` it is a plain native submit.
- Destroy is a `button_to` DELETE form; the client freshens its CSRF token
  from the meta tag first, since channel-rendered fragments have no session.
- The create form only comes from the channel, so a reload mid-create lands on `/books/new`.
- Infinite scroll is two elements: the wrapper is the `visible` sentinel with
  no `fallback:`; the Load-more link inside has `?page=N` and `fallback: true`.

## Live validation and field order

Live checks cover what a form can check from the typed value alone: presence,
length, numericality bounds without `allow_nil:`/`allow_blank:`. Validators
with `if:`, `unless:` or `on:` run at commit and mirror into the same slots.
Generated forms hold live errors until `dirty?`; commit errors always show. The
clauses are a snapshot: re-run `bin/rails g hibiki:rails:form Book` after adding validators.

Views render fields in argument order; with none it is `columns_hash` order,
alphabetical for a `schema.rb` app. A named field with no column is still generated.

## Post-install notices

| Tag | Warns about |
| --- | --- |
| `restart` | New `app/*` directories; autoload paths are computed at boot |
| `stale` | `app/models/book_query.rb` from before 0.13.0 still loads first |
| `css` | Stylesheet created and how it was linked (or that nothing links it); rebuild Tailwind |
| `motion` | `application.js` now imports `hibiki-rails/motion`, or was not found |
| `views` | Leftover ERB templates after `--phlex`, or stale shared views |
| `assoc` | Display label guessed as the parent's first string column |
| `order` | Field order came from the schema; the printed command sets it |
| `fields` | A named field the model has no column for |
| `form` | `live_errors` is empty; prints `bin/rails g hibiki:rails:form Book` |
| `unique` | Unique index with no validator: a duplicate raises `RecordNotUnique` in the channel while the busy indicator clears from an `ensure` |
| `skip` | A column with no form shape (rich text, password digest, polymorphic) |
| `hint` | The client is not wired; run `hibiki:rails:install` |
| `warn` | `--phlex` without `phlex-rails` or without `phlex:install` |

## Loading state and motion in the output

`hibiki_busy.css` maps the client's attributes onto five sites (counts
spinner, progress bar, Load-more link, destroy buttons, Save); buttons are
dimmed, never disabled, so focus survives. Its rules sit outside any `@layer`
to beat Tailwind utilities. Motion marks `#book_new` and `#book_7_edit`
(`data-motion`, `hbk-slide`) and `#book_7` (`data-motion="own"`, `hbk-slide-x`,
its own Destroy only); the `#book_7_display` wrapper lets a morph swap ids.

## Phlex instead of ERB

Only the view layer changes: the controller renders `Views::Books::Index.new(...)`
and the channels pass `renderable:` instead of `partial:`. Not hibiki_phlex:
here the channel owns state and the components are stateless.

| ERB | Phlex |
| --- | --- |
| `app/views/books/index.html.erb` | `app/views/books/index.rb` (`Views::Books::Index`) |
| `app/views/books/_book.html.erb` | `app/views/books/row.rb` (`Views::Books::Row`) |
| `app/views/books/_book_form.html.erb` | `app/views/books/row_form.rb` (`Views::Books::RowForm`) |

Four Phlex facts shape the code: non-string values get `to_s`; `data-turbo` is
the string `"false"` (a boolean vanishes); siblings are spaced explicitly;
select options come from a block. Sorting emits no `NULLS` clause, so empty
values land at opposite ends on SQLite and PostgreSQL; pin it per adapter.

See also: https://planetaska.github.io/hibiki/working-with-active-record/
Full docs: https://planetaska.github.io/hibiki/crud-notes/
