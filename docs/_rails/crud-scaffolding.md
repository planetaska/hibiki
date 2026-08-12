---
title: CRUD scaffolding
nav_order: 4
---

# CRUD scaffolding

`hibiki_rails` comes with its own scaffold generators. Just like `rails g scaffold` gives you a resource that works by reloading the page, Hibiki's scaffold generators give you the same resource, but **live**: search, filtering, sorting and pagination do not require page loads, rows edit in place, and a write from anywhere — another tab, another user, the plain controller, a console — re-renders every open index list.

Everything the generator needs is derived from the model's schema (columns, types, `belongs_to` reflections, validators), or from the same `field:type` argument list that Rails' own scaffold takes. Once it has run, reshape the result to fit your needs.

The output doubles as a worked example: several approaches were measured before settling on the pattern it emits. The guiding principle is that you should be able to build **on top of** the scaffold rather than tear it down and start over.

## Basic scaffold commands

### Two scaffold styles

You can run the scaffold in two styles:

#### 1. Full scaffold

```sh
bin/rails g hibiki:rails:scaffold RESOURCE_NAME FIELD:TYPE
```

The full scaffold creates the model, migration, fixtures, route and the reactive resource. It works just like a regular Rails scaffold.

Example:

```sh
# Full scaffold
bin/rails g hibiki:rails:scaffold Book title:string available:boolean author:references
bin/rails db:migrate
```

#### 2. Scaffold from an existing model

For a model you already have, use `scaffold_controller` like you would in regular Rails. The resource schema is derived from that model for you.

Example:

```sh
# The schema is automatically read for you
bin/rails g hibiki:rails:scaffold_controller Book
```

### Re-derive the form after adding validators

The live validation in the generated form is derived from the model's validators — and a full scaffold runs before its own migration, so it starts empty. Once you have migrated and added validators, we provide a convenient command to re-generate the reactive form with inferred live error messages:

```sh
# Rewrites the ReactiveForm and the two form views. Nothing else is touched.
bin/rails g hibiki:rails:form Book
```

It re-derives everything validator-shaped — the live validation clauses, a number field's `min:`/`max:`, requiredness — and leaves the rest of the scaffold's output alone. You are asked per file before anything you edited is replaced. Pass `--skip-views` to rewrite only `app/forms/book_form.rb`; the view layer and `--css` variant are detected from the files the scaffold left.

### Add a multi-select for a `has_many :through`

A scaffolded resource can attach a **searchable** dropdown multi-select over a join model — ideal for use cases like tagging songs onto an album. The join model will be generated for you if it doesn't exist yet:

```sh
# Adds a songs dropdown to the album's inline edit form; creates Track
# (and its migration) when missing
bin/rails g hibiki:rails:multiselect Album Song Track
```

The channel gains one `include`; everything else lives in a generated concern and a view partial. [Multi-select associations]({{ "/multiselect/" |
relative_url }}) covers the design — in particular why the selection lives in the graph, which is what lets the search filter narrow 100k options without ever dropping a checked one.

### Scaffolding with style

The scaffold supports Tailwind CSS and DaisyUI pre-built styling. To pick a variant, pass a `--css` argument.

Example:

```sh
# By default, the generator detects your project configuration
# This generates DaisyUI or Tailwind class names when available
bin/rails g hibiki:rails:scaffold Book title:string

# If you wish to pick a specific styling option:
bin/rails g hibiki:rails:scaffold Book title:string ... --css=tailwind
```

### Infinite scroll

The generator can create an infinite-scroll index page instead of a paginated one, backed by an `IntersectionObserver`. Because the index list is already reactive, the cost is minimal.

Example:

```sh
# Now /books will have infinite scroll instead of regular pagination
bin/rails g hibiki:rails:scaffold Book title:string ... --infinite-scroll
```

### Phlex support

Generating Phlex views is supported if you wish to use it. Pass `--phlex` and the generator writes Phlex component views instead of ERB templates.

Example:

```sh
# Phlex components instead of ERB templates in views/books/
bin/rails g hibiki:rails:scaffold Book title:string ... --phlex
```

### Rails' own resources are generated too

`hibiki:rails:scaffold` subclasses Rails' own resource generator, so the model, its migration, its fixtures and the route all come from Rails, unchanged. Everything a regular Rails resource gives you is still there when you need it — for third-party tooling, for instance.

Namespaced names work (`admin/book`), as they do for the [component-shape generators]({{ "/generators/" | relative_url }}).

## What the scaffold writes

Per resource, with `Book` as the example:

| File | What it is |
| --- | --- |
| `app/channels/books_channel.rb` | The list island's graph: a `db_version` token, the search/filter/sort/page signals, the `rows`/`counts`/`remaining` deriveds, one render effect, and the client-invocable actions |
| `app/channels/book_channel.rb` | The show page's graph — one record, held as a frozen read-only snapshot |
| `app/models/book_query.rb` | The query, in one place, plus `PAGE_SIZE` and the `SEARCHABLE`/`FILTERABLE`/`SORTABLE` allowlists. Its `rows` are frozen, read-only, `strict_loading` records — see [CRUD notes]({{ "/crud-notes/" | relative_url }}) |
| `app/forms/book_form.rb` | A [reactive form]({{ "/reactive-forms/" | relative_url }}) over the model’s attributes |
| `app/controllers/books_controller.rb` | Regular Rails scaffold; still serves the first render and the non-JS path |
| `app/views/books/*` | `index`/`show`/`new`/`edit` plus `_list`, `_book`, `_book_form`, `_form`, `_controls` (or the Phlex equivalents) |
| `app/views/shared/*` | The page control, the field-error line and the form-error summary — once per app, shared by every scaffolded resource. A second scaffold finds them and leaves them alone |
| `app/assets/stylesheets/hibiki_busy.css` | The loading and connection styles. Per app — a second scaffold finds it and leaves it alone |

## Options

| Option | Effect |
| --- | --- |
| `--css=NAME` | Class-name markup variant for every generated view: `daisyui`, `tailwind` or `none`. Absent means detect — daisyUI, then Tailwind, then stock. |
| `--infinite-scroll` | Grow the page on scroll instead of paginating it |
| `--skip-pagination` | Skip pagination altogether |
| `--skip-search` | Omit the search box and the `LIKE` terms behind it |
| `--page-size=N` | Rows per page (default 20) |
| `--skip-routes` | Don't touch `config/routes.rb` |
| `--phlex` | Phlex components under `app/views/<resource>/` instead of ERB templates |

## What to do next

The generated app is a **starting point**. Every file it writes is ordinary Rails code with no gem-side magic reading it back, and the generator stops owning a file the moment it writes it. Reshape it as needed.

The most common next steps:

- **Restart the server after the first run.** `app/forms/` is almost certainly a new directory, and Rails computes its autoload paths at boot — until you restart, the new constants raise `NameError`.
- **Add validators to the model**, then run `bin/rails g hibiki:rails:form Book` to derive the live validation clauses from them — or write the clauses into the form by hand.
- **Add a multi-select over a join** with `bin/rails g hibiki:rails:multiselect Book Tag BookTag` — see [Multi-select associations]({{ "/multiselect/" | relative_url }}).
- **Reorder or drop fields** in the views.

And to understand what you were handed:

- [CRUD notes]({{ "/crud-notes/" | relative_url }}) — what the generator modifies in files you already own, the post-install notices, and the choices behind the output.
- [The JS client]({{ "/the-js-client/" | relative_url }}) — the island, the helpers, the events, and the loading/connection attributes.
- [Reactive values]({{ "/reactive-values/" | relative_url }}) — the counts sentence and the sort label, which live outside the replaced fragment.
- [Reactive forms]({{ "/reactive-forms/" | relative_url }}) — what `app/forms/book_form.rb` is.
- [Working with ActiveRecord]({{ "/working-with-active-record/" | relative_url }}) — the version-signal pattern the channel is built on, and the `after_commit`
  bridge the model injection writes for you.
- [Broadcast helpers]({{ "/broadcast-helpers/" | relative_url }}) — why the list is morphed rather than replaced, and what a channel-rendered partial can and cannot read.
