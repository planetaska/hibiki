---
title: CRUD scaffolding
nav_order: 4
---

# CRUD scaffolding

To help increase productivity, `hibiki_rails` comes with its own sets of scaffolding. Just like `rails g scaffold` gives you a resource that works by reloading the page, Hibiki's scaffold generators give you the same resource, but **live**: search, filtering, sorting and pagination do not require page loads, rows edit in place, and a write from anywhere — another tab, another user, the plain controller, a console — re-renders every open index list.

By default, every required information for resources is derived from the model's schema (columns, types, `belongs_to` reflections, validators), or from the same `field:type` argument list that Rails' own scaffold takes. Once generated, you can then customize the scaffolded resource to fit your needs.

The generator also serves as a best practice example. We tested different approaches and measured the best pattern for a reactive scaffold. The core concept for the generator is: you should be able to build on top of the scaffold, not tearing down and rebuild.

## Basic scaffold commands

You can run the scaffold in two styles:

#### 1. Full Scaffold

```sh
bin/rails g hibiki:rails:scaffold RESOURCE_NAME FIELD:TYPE
```

The full scaffold creates: model, migration, fixtures, route, and the reactive resource. It works just like regualr Rails scaffolds.

Example:

```sh
# Full scaffold
bin/rails g hibiki:rails:scaffold Book title:string available:boolean author:references
bin/rails db:migrate
```

#### 2. Scaffold from existing model

For existing model, use `scaffold_controller` like you would in regular Rails. The resource schema is automatically derived from your existing model.

Example:

```sh
# The schema is automatically read for you
bin/rails g hibiki:rails:scaffold_controller Book
```

#### Scaffolding with style

Hibiki's scaffold supports TailwindCSS and DaisyUI if you wish to use them for styling, and provides a basic pre-built style for you. If you wish to use them, simply add a `--css` argument for the scaffold.

Example:

```sh
# This creates reactive views with TailwindCSS styling
bin/rails g hibiki:rails:scaffold Book title:string ... --css=tailwind

# Or if you have DaisyUI installed
bin/rails g hibiki:rails:scaffold Book title:string ... --css=daisyui
```

#### Infinite scroll

The generator can also generator a basic infinite scroll page for you. This is achieved with IntersectionObserver. Since Hibiki is a reactive library, supporting infinite scroll becomes trivial and comes with minimal overhead.

Example:

```sh
# Now /books will have infinite scroll instead of regular pagination
bin/rails g hibiki:rails:scaffold Book title:string ... --infinite-scroll
```

#### Phlex support

Phlex is supported if you wish to use it. The generator will now create Phlex component views instead of regular ERB pages.

Example:

```sh
# Phlex components instead of ERB templates in views/books/
bin/rails g hibiki:rails:scaffold Book title:string ... --phlex
```

#### Rails's own resources are also generated

`hibiki:rails:scaffold` subclasses Rails' own resource generator, so the model, its migration, its fixtures and the route all come from Rails, unchanged. This way, you can expect all regular Rails resources are still available when you need them (e.g for third party tools).

Namespaced names work (`admin/book`), as they do for the [component-shape generators]({{ "/generators/" | relative_url }}).

## What the scaffold writes

Per resource, with `Book` as the example:

| File | What it is |
| --- | --- |
| `app/channels/books_channel.rb` | The list island's graph: a `db_version` token, the search/filter/sort/page signals, the `rows`/`counts`/`remaining` deriveds, one render effect, and the client-invocable actions |
| `app/channels/book_channel.rb` | The show page's graph — one live record |
| `app/models/book_query.rb` | The query, in one place, plus `PAGE_SIZE` and the `SEARCHABLE`/`FILTERABLE`/`SORTABLE` allowlists |
| `app/models/book_row.rb` | A `Data` projection: one plain value per row, so the graph never holds a live record |
| `app/forms/book_form.rb` | A [reactive form]({{ "/reactive-forms/" | relative_url }}) over the model’s attributes |
| `app/controllers/books_controller.rb` | Regular Rails scaffold; still serves the first render and the non-JS path |
| `app/views/books/*` | `index`/`show`/`new`/`edit` plus `_list`, `_book`, `_book_form`, `_form`, `_controls`, `_pagination`, `_field_error` (or the Phlex equivalents) |
| `app/assets/stylesheets/hibiki_busy.css` | The loading and connection styles. Per app — a second scaffold finds it and leaves it alone |

## Options

| Option | Effect |
| --- | --- |
| `--css=NAME` | Class name markup variant for every generated view: `daisyui`, `tailwind` or `none`. Absent means detect — DaisyUI, then Tailwind, then stock. |
| `--infinite-scroll` | Grow the page on scroll instead of standard pagination |
| `--skip-pagination` | Skips pagination altogether |
| `--skip-search` | Omit the search box and the `LIKE` terms behind it |
| `--page-size=N` | Rows per page (default 20) |
| `--skip-routes` | Don't touch `config/routes.rb` |
| `--phlex` | Phlex components under `app/views/**.rb` instead of ERB templates |

## What to do next

The generated app is a **starting point**. Every file it writes is ordinary Rails code with no gem-side magic reading it back, and the generator stops owning a file the moment it writes it. Reshape it as needed.

The most common next steps:

- **Add validators**, then add by hand or re-run `scaffold_controller` to derive the live validation messages from them.
- **Reorder or drop fields** in the views.
- **Restart server after the first time you ran the generator**.

And to understand what you were handed:

- [The JS client]({{ "/the-js-client/" | relative_url }}) — the island, the helpers, the events, and the loading/connection attributes.
- [Reactive values]({{ "/reactive-values/" | relative_url }}) — the counts sentence and the sort label, which live outside the replaced fragment.
- [Reactive forms]({{ "/reactive-forms/" | relative_url }}) — what `app/forms/book_form.rb` is.
- [Working with ActiveRecord]({{ "/working-with-active-record/" | relative_url }}) — the version-signal pattern the channel is built on, and the `after_commit`
  bridge the model injection writes for you.
- [Broadcast helpers]({{ "/broadcast-helpers/" | relative_url }}) — why the list is morphed rather than replaced, and what a channel-rendered partial can and cannot read.
