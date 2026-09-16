# CRUD scaffolding (digest)

`hibiki:rails:scaffold` is `rails g scaffold` with a live resource on top:
search, filter, sort and paging update the index in place; create and edit
happen inline; a write from anywhere updates every open index. The same page
works with the socket down or without JavaScript.

## The two commands

```sh
# New resource: Rails' own resource generator writes model, migration, fixtures, route
bin/rails g hibiki:rails:scaffold Book title:string available:boolean author:references
bin/rails db:migrate

# Existing model: columns, types, belongs_to and validators read from the model
bin/rails g hibiki:rails:scaffold_controller Book
```

After the first run: restart the server (`app/forms/`, `app/queries/` are new
autoload roots) and read the output (three owned files are modified). The full
scaffold needs at least one field, because it runs before its own migration.
`scaffold_controller` with no fields reads the schema; with fields, the
arguments choose the order and the model still answers everything else.
Namespaced names (`admin/book`) work.

## What the pages do

- Live index: search box, filter selects, sortable column, page control or
  infinite scroll; counts sentence and sort label update with it.
- Inline create at the top of the list; `/books/new` still exists.
- Inline edit per row; Save writes and the row returns to display.
- Live validation per field, from the model's validators.
- Show page is live; new and edit pages are standard Rails pages and the
  fallback for the inline forms.

How: the channel holds the search, filters, sort, direction and page as
signals, seeded from the URL at subscribe. `rows` is a derived that runs
`BookQuery`; one effect renders `_list` and morphs it in. `db_version` is the
extra signal other writers reach through the model's `after_commit` ping.

## Options

| Option | Effect |
| --- | --- |
| `--css=NAME` (`daisyui`, `tailwind`, `none`) | Absent means detect: daisyUI, then Tailwind, then none |
| `--infinite-scroll` | Grow on scroll; Load-more keeps a real `?page=N` href |
| `--skip-pagination` | `PAGE_SIZE = nil`; the index lists every row |
| `--skip-search` | No search box, no `LIKE` terms, no `search` action |
| `--skip-create` | No inline create; New always navigates |
| `--skip-motion` | No `hibiki_motion.css`, no import, no marks |
| `--page-size=N` | Rows per page (default 20) |
| `--phlex` | Phlex components under `app/views/books/*.rb` |
| `--skip-routes` | `scaffold_controller` only; the full scaffold takes Rails' `--skip-resource-route` |

Motion is three pieces: `data-motion` plus a class on each moving element,
`hibiki_motion.css` holding the transitions, and `import "hibiki-rails/motion"`
in `application.js` holding a re-render until a leaving element finishes.
`--css=none` writes none of it (the transitions are Tailwind utilities), so it
equals `--skip-motion`. `--phlex` changes only the view layer and needs
`phlex-rails` plus `bin/rails g phlex:install`.

## What it writes

| File | Role |
| --- | --- |
| `app/channels/books_channel.rb` | Index graph: signals, `rows` and `counts` deriveds, one render effect, `transmit_value` names, `transmit_url`, the actions |
| `app/channels/book_channel.rb` | Show page: one frozen record |
| `app/queries/book_query.rb` | `PAGE_SIZE`, `SEARCHABLE`, `FILTERABLE`, `SORTABLE`; `from_params` in, `url_params` out; frozen `strict_loading` rows |
| `app/forms/book_form.rb` | ReactiveForm: one signal per field plus `live_errors` |
| `app/controllers/books_controller.rb` | Regular scaffold controller; initial page and every no-JS request |
| `app/views/books/*` | `index`, `show`, `new`, `edit`, `_list`, `_book`, `_book_form`, `_form`, `_controls` (or Phlex twins) |
| `app/views/shared/*` | Page control, field-error line, form-error summary; once per app |
| `app/assets/stylesheets/hibiki_busy.css` | Loading and connection styles; once per app |
| `app/assets/stylesheets/hibiki_motion.css` | Slide transitions; once per app, plus the `application.js` import |

Nothing in the gem reads these files back; the generator stops owning them.

## Add to the resource

Run in any order; each writes what it adds and leaves the rest alone.

```sh
bin/rails g hibiki:rails:form Book                      # re-derive form + two form views after validators change (--skip-views: form only)
bin/rails g hibiki:rails:multiselect Album Song Track   # dropdown over has_many :through; creates Track if missing
bin/rails g hibiki:rails:nested Song Credit role:string position:integer   # live fields_for; creates Credit if missing
bin/rails g hibiki:rails:upload_field Album cover       # Active Storage; --many, --accept=image,pdf
```

These four are covered by the `hibiki-rails-forms` skill.

Full docs: https://planetaska.github.io/hibiki/crud-scaffolding/
