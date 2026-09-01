---
title: CRUD scaffolding
nav_order: 4
---

# CRUD scaffolding

`rails g scaffold` gives you a whole resource: a model, a migration, a
controller, and the index, show, new, and edit pages. Every change reloads
the page. `hibiki_rails` ships a scaffold of its own that gives you the same
resource, **live**. Search, filtering, sorting, and paging update the list
without a page load. Rows are created and edited in place, on the index page
itself. And a write from anywhere, whether another tab, another user, a
console session, or the plain controller, updates every open index.

The live page also works without the live part. It is built from real links
and real forms, the address bar follows the live state, and the plain Rails
controller still answers every request. The same page works with the socket
down, or with no JavaScript at all.

You do not need to know how signals work to run the scaffold. The output is
ordinary Ruby that you will read and edit, though, so this page explains the
moving parts in plain words as it goes. If you would rather have the whole
idea first, start from the [Rails introduction]({{ "/rails-introduction/" | relative_url
}}).

## Generate a resource

There are two commands, mirroring Rails' own pair.

**For a new resource**, pass the model name and a field list, exactly as you
would to `rails g scaffold`:

```sh
bin/rails g hibiki:rails:scaffold Book title:string available:boolean author:references
bin/rails db:migrate
```

This writes the model, the migration, the fixtures, and the route, and then
the live resource on top of them. The Rails pieces come from Rails' own
resource generator, unchanged, so anything that expects a regular Rails
resource can still find one.

**For a model you already have**, use `scaffold_controller`. The generator
reads the columns, their types, the `belongs_to` associations, and the
validators from the model, so there is no field list to type:

```sh
bin/rails g hibiki:rails:scaffold_controller Book
```

Two things to know about the first run:

- **Restart the server.** The scaffold writes `app/forms/`, which is almost
  certainly a new directory, and Rails computes its autoload paths at boot.
  Until you restart, the new constants raise `NameError`.
- **Read the output.** The generator edits three files you already own: the
  model, every model a `belongs_to` points at, and `config/routes.rb`. Each
  edit is announced, and each leaves what you already declared alone.
  [CRUD notes]({{ "/crud-notes/" | relative_url
  }}#what-the-generator-changes-in-files-you-already-own) lists the edits and
  the reasons for them.

Namespaced names work (`admin/book`), as they do for the
[component-shape generators]({{ "/generators/" | relative_url }}).

## What the generated pages do

If you ran the scaffold command above, visit `/books` and you will find:

- **A live index list.** Typing in the search box, choosing a filter, clicking a
  column header to sort, or moving to another page updates the list *in place*.
  The counts sentence above the list and the sort label update with it.
- **Inline create.** The New link opens a create form at the top of the list.
  The standard `/books/new` page is still generated and still reachable.
- **Inline edit.** Each row's Edit link turns the row into a form, in place.
  Save writes the record, and the row goes back to being a row.
- **Live validation.** The inline forms check each field as it is filled in,
  using the rules derived from the model's validators.
- **Updates from anywhere.** A record created in the console, changed by a
  background job, or edited in another user's tab updates every open index.

The show page is live too: it updates when its record changes. The new and
edit pages are the standard Rails pages, and the inline forms fall back to
them when JavaScript is unavailable.

### How the live list works

Everything the index shows is computed from a handful of values kept on the
server: the search text, the active filters, the sort column and direction,
and the page number. In Hibiki each of these is a *signal*, a value that
remembers who read it. The generated channel holds them, and every browser
tab gets its own set.

Two more kinds of value sit around those signals. A *derived* value, `rows`,
runs the query, and it depends on every signal it read while doing so. An
*effect* renders the list partial from `rows` and sends the HTML down to the
browser. Neither of them declares what it depends on. Hibiki records the
dependencies as they are read.

So one click travels a fixed path. The client sends the action to the
channel. The action writes a signal, say the page number. That makes `rows`
out of date, so the effect that read it re-runs, and the new list HTML
travels back down and replaces the old one. Nothing else on the page moves.
(The [Rails introduction]({{ "/rails-introduction/" | relative_url
}}#what-happens-on-a-click) walks through the same four steps if you are not familiar.)

The above path covers the writes one browser tab makes. The database has other writers:
a console session, a background job, the plain controller, another user's
tab. Signals only notice writes made to them, so a row saved anywhere else
would leave every open index stale. One more signal is how writes from
elsewhere get in: a counter the channel calls `db_version`, which `rows`
reads before running the query. The generator adds an `after_commit`
callback to the model, and after any commit the callback pings every open
channel for that resource. Each channel bumps its own counter, `rows` goes
out of date, and the list re-renders by the same path a click takes.
[Working with ActiveRecord]({{ "/working-with-active-record/" | relative_url
}}#other-writers-bridging-after_commit-into-the-graph) explains the pattern
and why records themselves stay out of signals.

## What the scaffold writes

Per resource, with `Book` as the example:

| File | What it is |
| --- | --- |
| `app/channels/books_channel.rb` | The index page's signals and effects: `db_version`, the search, filter, sort, and page signals, seeded from the URL at subscribe time, the `rows` and `counts` derived values, one render effect plus the address-bar mirror, and the actions the client can invoke, including row edit and inline create |
| `app/channels/book_channel.rb` | The show page's channel: one record, held as a frozen read-only snapshot |
| `app/models/book_query.rb` | The query, in one place, with `PAGE_SIZE`, the `SEARCHABLE`, `FILTERABLE`, and `SORTABLE` allowlists, and the URL half: `from_params` in, canonical `url_params` out. Its `rows` are frozen, read-only, `strict_loading` records, for reasons [CRUD notes]({{ "/crud-notes/" | relative_url }}#why-the-rows-come-back-frozen) gives |
| `app/forms/book_form.rb` | A [reactive form]({{ "/reactive-forms/" | relative_url }}) over the model's attributes: one signal per field, plus the live validation clauses |
| `app/controllers/books_controller.rb` | A regular Rails scaffold controller. It serves the initial server-rendered page and every request made without JavaScript |
| `app/views/books/*` | `index`, `show`, `new`, and `edit`, plus the `_list`, `_row`, `_row_form`, `_form`, and `_controls` partials, or their Phlex equivalents |
| `app/views/shared/*` | The page control, the field-error line, and the form-error summary. Written once per app and shared by every scaffolded resource; a second scaffold finds them and leaves them alone |
| `app/assets/stylesheets/hibiki_busy.css` | The loading and connection styles. Once per app, like the shared views |

Every file is ordinary Rails code. Nothing in the gem reads it back, and the
generator stops owning a file the moment it writes it, so you can build on top of the output
and change anything to your like.

## The address bar, and life without JavaScript

Two behaviours of the generated index are worth knowing before you build on
it.

**The address bar follows the live state.** Search, filter, sort, and page
live in the channel's signals, and the channel keeps the matching query
params in the bar (`/books?query=ruby&page=2`) through
[`transmit_url`]({{ "/reactive-values/" | relative_url
}}#mirroring-the-address-bar-with-transmit_url). It uses `replaceState`, so no history
entries pile up and the Back button behaves normally. An open inline form
mirrors its own URL (`/books/7/edit`, `/books/new`). A reload, or a link
handed to someone else, brings the page back in that exact state.

**Every control has a path without JavaScript.** The New and Edit links carry
real hrefs to the standard pages. The Destroy button is a real `button_to`
DELETE form. The search, filter, and sort controls are one GET form to the
index, and the page control's links carry real `?page=N` hrefs. When
JavaScript is unavailable, the browser does what the markup says, and the
Rails controller answers with a full page.

The one deliberate exception is `--infinite-scroll`, whose load-more control
has no paginated fallback. [CRUD notes]({{ "/crud-notes/" | relative_url
}}#the-address-bar-and-life-without-javascript) covers both behaviours in
more depth, and walks the fallback paths one by one.

## Options

Both scaffold commands take the same options:

| Option | Effect |
| --- | --- |
| `--css=NAME` | Class-name variant for every generated view: `daisyui`, `tailwind`, or `none`. Absent means detect: daisyUI first, then Tailwind, then plain markup |
| `--infinite-scroll` | Grow the list on scroll instead of paginating it |
| `--skip-pagination` | No paging at all; the index lists every row |
| `--skip-search` | Omit the search box and the `LIKE` terms behind it |
| `--skip-create` | Omit the inline create form, so the New link always navigates to `/books/new` |
| `--page-size=N` | Rows per page (default 20) |
| `--phlex` | Phlex components under `app/views/books/` instead of ERB templates |
| `--skip-routes` | Leave `config/routes.rb` alone. `scaffold_controller` only; the full scaffold takes Rails' own `--skip-resource-route` |

A few of them deserve a sentence.

**Styling.** With no `--css`, the generator looks at your project and writes
daisyUI or Tailwind class names when it finds either, and plain markup
otherwise. Pass the option to choose for yourself:

```sh
bin/rails g hibiki:rails:scaffold Book title:string ... --css=tailwind
```

**Infinite scroll.** The index grows as the reader scrolls, driven by an
`IntersectionObserver`. Because the list is already live, the change is
small, but this is the one control with no fallback when JavaScript is
unavailable:

```sh
bin/rails g hibiki:rails:scaffold Book title:string ... --infinite-scroll
```

**Phlex.** The generator writes Phlex components instead of ERB templates.
The view layer is the only thing that changes. See
[Phlex support]({{ "/phlex-support/" | relative_url }}) for what the gem
needs in place first:

```sh
bin/rails g hibiki:rails:scaffold Book title:string ... --phlex
```

## Add to the resource

Four more generators build on a scaffolded resource. Each writes what it
adds and leaves the rest of the scaffold's output alone. Run them in any
order, and re-run the first whenever the model's validators change.

### Re-derive the form after adding validators

The live validation in the generated form comes from the model's validators.
A full scaffold runs before its own migration, so its form starts with no
checks. Once you have migrated and added validators, one command re-derives
the form, with live error messages inferred from each validator:

```sh
# Rewrites the reactive form and the two form views. Nothing else is touched.
bin/rails g hibiki:rails:form Book
```

It re-derives everything that follows from a validator: the live validation
clauses, a number field's `min:` and `max:`, and which fields are required.
It asks per file before replacing anything you edited. Pass `--skip-views` to
rewrite only `app/forms/book_form.rb`. The view layer and the `--css`
variant are detected from the files the scaffold left.

### Add a multi-select over a `has_many :through`

A scaffolded resource can take a searchable dropdown multi-select over a join
model, for cases like tagging songs onto an album. The generator creates the
join model when it does not exist yet:

```sh
# Adds a songs dropdown to the album's inline edit form; creates Track
# (and its migration) when missing
bin/rails g hibiki:rails:multiselect Album Song Track
```

The channel gains one `include`. Everything else lives in a generated concern
and a view partial. [Multi-select associations]({{ "/multiselect/" |
relative_url }}) covers the design, and in particular why the selection is
kept in signals on the server, which is what lets the search box narrow
100,000 options without ever dropping a checked one.

### Nest a child collection into the form

A scaffolded resource can nest a child collection into its forms, as a live
`fields_for`. Rows are added, edited, reordered, and removed with the form
still open, and one save persists the whole tree. The generator creates the
child model from the field list when it does not exist yet:

```sh
# Adds a credits fieldset to the song's forms; creates Credit
# (and its migration) when missing. song:references is added for you.
bin/rails g hibiki:rails:nested Song Credit role:string position:integer
```

Each run wires one parent-to-child edge. Run it again with the child as the
parent and the nesting goes a level deeper. [Nested forms]({{
"/nested-forms/" | relative_url }}) covers the design: the child forms live
in signals on the server, addressed by path, while the classic `fields_for`
page form stays as the path without JavaScript.

### Add file uploads

A scaffolded resource can take an Active Storage attachment on both the
classic page form, which uploads on submit, and the inline edit form, which
uploads as soon as a file is picked:

```sh
# Adds a cover upload to the album's forms, and a thumbnail to its rows
bin/rails g hibiki:rails:upload_field Album cover

# Adds a gallery, and allows non-image files
bin/rails g hibiki:rails:upload_field Album photos --many --accept=image,pdf
```

[File uploads]({{ "/file-uploads/" | relative_url }}) covers the design and
the generator in more detail.

## Where to read next

The generated resource is a starting point, and the most common edits are
reordering or dropping fields in the views and reshaping the query object.
To understand what you were handed:

- [CRUD notes]({{ "/crud-notes/" | relative_url }}) explains what the
  generator changes in files you already own, the post-install notices, and
  the choices behind the output.
- [The JS client]({{ "/the-js-client/" | relative_url }}) covers the island,
  the helpers, the events, and the loading and connection attributes.
- [Reactive values]({{ "/reactive-values/" | relative_url }}) covers the
  counts sentence and the sort label, which live outside the re-rendered
  list.
- [Reactive forms]({{ "/reactive-forms/" | relative_url }}) explains what
  `app/forms/book_form.rb` is.
- [Working with ActiveRecord]({{ "/working-with-active-record/" |
  relative_url }}) covers the version signal the channel is built on, and
  the `after_commit` bridge the generator writes into the model.
- [Broadcast helpers]({{ "/broadcast-helpers/" | relative_url }}) explains
  why the list is morphed rather than replaced, and what a partial rendered
  from a channel can and cannot read.
