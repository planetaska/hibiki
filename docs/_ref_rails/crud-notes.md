---
title: CRUD notes
nav_order: 9
---

# CRUD notes

Background for [`hibiki:rails:scaffold`]({{ "/crud-scaffolding/" | relative_url
}}): what it changes in files you already own, why the generated code looks
the way it does, and what each post-install notice is warning you about. None
of it is needed to run the generator — read these notes before you start
reshaping the output, or when something the generator emitted surprises you.

These notes lean on a few words the rest of the docs use everywhere, so here
they are in one breath. In a scaffolded app, the page's state — the search
query, the sort, the page number, the row being edited — lives on the
**server**, inside an ActionCable channel, as **signals**: values that track
who reads them. A **derived** is a value computed from signals, recomputed when
they change. An **effect** is code that re-runs when a value it read changes —
the channel's render effect is what re-renders HTML fragments and sends them
down the socket. Together these make up the channel's **graph**. On the page,
the region those fragments land in is the **island**. If any of this is new,
[the Rails introduction]({{ "/rails-introduction/" | relative_url }})
introduces each in context.

## What the generator changes in files you already own

This is the part that separates `hibiki:rails:scaffold` from
`rails g scaffold`, and the part to know before you run it against an app you
already built and care about: **three files you already own are modified**.
For example, scaffolding `Book` with `author:references` modifies:

- the model itself — `app/models/book.rb`
- the model its `belongs_to` points at — `app/models/author.rb`
- `config/routes.rb`

All three edits are idempotent, all are announced in the output, and all
leave anything you already declared alone.

**The model being scaffolded** gains an `after_commit` callback, and the whole
thing hangs off it. The signals live on the server, but nothing tells them a
row changed — a write from a console, a background job or another user's
browser would leave every open index stale. The injected callback is the
bridge: after any commit it pings the channel, and the graph re-queries. The
pattern behind it is covered in
[Working with ActiveRecord]({{ "/working-with-active-record/" | relative_url
}}#other-writers-bridging-after_commit-into-the-graph).

**Every model a `belongs_to` points at** gains two things, which Rails' own
`author:references` never writes:

- the **`has_many` half** of the association — without it, the destroy button
  this generator emitted raises `ActiveRecord::InvalidForeignKey`;
- **a broadcast ping of its own** — the generated index page shows each book's
  author by *name*, not by `author_id`, so a book's row goes stale when its
  author changes. The ping is what keeps the index fresh: rename an author
  from any source, and every open books index updates with the new name.

**`config/routes.rb`** gains `resources :books`, unless `--skip-routes`.

## Two behaviors of the injected code

The edits above carry two behaviors worth stating outright, rather than
leaving you to discover them.

### `dependent:` follows the association, not the column

The injected `has_many` has to answer a question: when an author is
destroyed, what happens to their books? The generator answers it by reading
the `belongs_to` declaration:

- required association → `dependent: :destroy` — the books go with the author;
- `optional: true` → `dependent: :nullify` — the books stay, their
  `author_id` cleared.

The other place the generator could have looked is the `author_id` column:
does the database allow it to be `NULL`? But the column routinely disagrees
with the association — Rails' `belongs_to_required_by_default` makes the
association required in the model while the column underneath still allows
`NULL`. Read the column there, and the generator would pick `:nullify` —
leaving books that fail their own presence validation on their next save. So
the generator reads the association: the declaration you actually wrote. And
if it guessed wrong, change the line — re-running the generator will leave
your choice alone.

### The parent's ping updates indexes, not show pages

In the book-author example, renaming an author updates every open books
**index**, while an open book **show** page keeps the stale author name
until it is reloaded. This limit is a cost decision: a show page listens
on its own book's stream, so reaching them all would mean loading every one
of the author's books inside the callback — unbounded, on every author
write. Pinging the books collection instead is one broadcast, however many
books there are. The injected ping carries a comment saying so, because
without it the stale show page reads as a bug.

## Why the rows come back frozen

Hibiki decides whether to re-render by comparing values. A signal written the
value it already holds notifies no subscriber, and an effect re-runs only
when a value it read has changed. A gesture that changes nothing — a save
with no edits, a filter set to the value it already holds — therefore renders
nothing, which is correct.

The comparison is `==`, and `ActiveRecord::Base#==` compares **class and id
only**. By that definition, a record re-queried after an edit is equal to the
stale record it replaces — hibiki would conclude nothing changed, and skip
the re-render.

The generated code prevents this in two places. First, the channel's `rows`
derived compares records by their attributes instead, through
[the `equals:` option]({{ "/working-with-active-record/" | relative_url
}}#an-opt-in-upgrade-comparing-records-by-attributes); the show channel's
`row` derived carries the same comparator:

```ruby
# app/channels/books_channel.rb

# `record_equals` compares by class and attributes, so an edited row
# counts as changed where ActiveRecord's id-only == would not.
@rows = Hibiki::Derived.new(equals: Hibiki::Rails.record_equals) do
  @db_version.value # the tracked dependency
  BookQuery.new(query: @query.value, filters: ...).rows
end
```

Second, the query makes every record immutable before handing it to that
derived, so the mistakes a comparison cannot catch raise instead of going
stale:

```ruby
# app/models/book_query.rb

# freeze locks the attributes — a write raises FrozenError.
# readonly! makes save raise ActiveRecord::ReadOnlyRecord.
# strict_loading makes walking an association the query didn't preload
# raise, instead of firing a lazy query from inside the graph.
def rows
  @rows ||= window_scope.strict_loading.map { it.readonly!; it.freeze }
end
```

Scaffolded before 0.6.0? Those scaffolds projected rows through a generated
`book_row.rb` `Data` class instead. It keeps working, and a `--force` re-run
moves the app over and leaves the now-dead file for you to delete.
{: .note }

## Why the query lives in one file

The index list is rendered by two different pieces of code: the controller,
on the initial request, and the channel's `rows` derived on every update
after it. Both
must apply the same window — the same search, filters, sort and page size —
and a scope hand-copied into the controller is exactly where the two drift
apart. `book_query.rb` exists so there is nothing to copy: both sides call the
same object. It lives in `app/models` rather than a tidier `app/queries`
because Rails computes autoload paths from the `app/*` glob at boot — see
[the post-install notices](#read-the-post-install-output) below.

## Pagination can be toggled by switching one constant

The `PAGE_SIZE` constant in `book_query.rb` is the pagination switch: a
number sets the rows per page, and `nil` turns pagination off —
`--skip-pagination` does nothing more than emit `nil` there. The `nil` works
because `.limit(nil)` and `.offset(nil)` are both relation no-ops: the page
count is permanently 1,
`remaining` is permanently 0, no page control renders, and `#go_to_page`
short-circuits on its first guard. One constant instead of
`<% if paginated? %>` branching across five files — and an example of how the
generated code is meant to be edited: if you change your mind later, just set
the constant.

## The address bar, and life without JavaScript

Two behaviors (0.8.0) are worth understanding together, because they are one
machinery seen from two sides.

**The address bar mirrors the graph.** When search, filter, sort or page
changes, the channel rewrites the query params
(`/books?query=ruby&page=2`) through
[`transmit_url`]({{ "/reactive-values/" | relative_url
}}#the-url-sibling-transmit_url) — using `replaceState`, so Back behaves
normally. An open inline form shows its own URL (`/books/7/edit`,
`/books/new`). Every such URL rebuilds its exact state on load: the
controller renders the initial page from the params (`BookQuery.from_params`),
and the island seeds the channel with the same params, so the graph starts
where the page left off. A reload or a shared link works as expected.

**Every control's native behavior is its fallback.** Each control is real
markup: New and Edit carry real hrefs, Destroy is a real `button_to` DELETE
form, search/filter/sort are one GET form to the index, and the page links
carry real `?page=N` hrefs. While the island is live, the JS client
intercepts each gesture (`fallback: true`) and the channel answers without a
page load. Otherwise — connecting, offline, stalled, or no JavaScript at
all — the browser follows the markup, and the controller answers with a full
page in the same state. One set of markup, three levels of service.

The fallback contract itself — when the client stands aside, how a
dead-but-undetected socket falls through, why native submits get their CSRF
token freshened — is documented in
[The JS client]({{ "/the-js-client/" | relative_url
}}#falling-back-to-native-behavior).

One deliberate exception: under `--infinite-scroll` the load-more control has
no deep-pagination fallback. It doubles as the scroll sentinel, and a control
that navigates on a dead socket would make *scrolling* navigate — so a
degraded infinite index shows the first window only.

## The fallback paths, piece by piece

The section above covers what falls back; these notes are for when you modify
the pieces, because several of them look redundant until you know what they
are holding up.

**The island's subscribe params look redundant; they are not.** The index
page tells the channel where to start: when it subscribes, it passes along
the current URL params
(`hibiki_island(..., params: @book_query.url_params.presence)`). Without
them, the channel would start every signal at its default — page 1, empty
query — no matter what URL the reader loaded. The failure would even hide
for a moment: open `/books?query=ruby&page=2` and the initial page is
correct, because the controller read the URL — then the graph's first
render replaces it with the default page 1, because nobody told the graph.
Passing the params on subscribe is what keeps the controller and the graph
in agreement.

One more consequence of arriving on the subscription: these params are
client input, as untrusted as any request params. The channel therefore
feeds them through the same allowlist normalizers the controller uses
(`filters_from`, `sort_from`, …) — never raw into a signal.

**The controls form intercepts its submit with `reset: false`.** The
controls form is the one GET form that holds the search box and the filter
and sort selects. When the JS client intercepts a form submit, its default
is to reset the form afterwards — right for an "add" form, whose fields
should empty for the next entry. In the controls form it would be wrong:
press Enter in the search box, and the reset would blank the query you just
searched for. `reset: false` turns the reset off.
(Under `--skip-search` there is no `search` action to aim the submit at, so
the form isn't intercepted at all: Apply is a plain native GET even while
live — the changed selects have already sent their own actions, and the
reload lands on the same mirrored state.)

**The direction button submits the opposite value.** It is a `submit` button
named `direction` carrying the *opposite* of the direction on screen: live, the
click is intercepted and toggles; dead, it submits the controls form with the
direction the user asked for. The value goes stale after live toggles — the
button is never re-rendered; its visible label is a reactive value — but the
dead path always begins from a fresh page, so a stale value is never actually
submitted.

**The destroy form is tokenless after the first channel update, by
construction.** Fragments rendered over the channel come from
`ApplicationController.render`, which has no session, so every `button_to`
inside them carries an empty `authenticity_token` — and the first broadcast
replaces the initial server-rendered fragment seconds after the page loads.
The client freshens the token from the `csrf-token` meta tag before any
native submit; a page where scripts never ran still holds the token it was
served with. If you add your own destructive control inside the island, keep
it a real form with `fallback: true` and the same machinery covers it.

**The inline create form only ever comes from the channel.** The first page
visit never renders it — `creating` is a signal in the graph, flipped by the
New link's action — so reloading mid-create lands on the standard
`/books/new` page. The create form is the same row-form partial re-aimed at
the `*_new` actions, with its own
[`ReactiveForm`]({{ "/reactive-forms/" | relative_url }}) instance so an open
row edit and an open create never share state.

## Live validation checks only what a form can check

Per-field errors appear as you type, and they are derived from the model's
validators — but only from the rules a form can check against the typed
value alone, before any save is attempted: presence, length, and numericality
bounds that carry no `allow_nil:`/`allow_blank:` exemption for the value in
hand.

A validator gated on `if:`, `unless:` or `on:` depends on the whole record
rather than on one field's value, so the form leaves it out of the
as-you-type checks. The validator rule still holds: it runs at every
commit, lands in `#errors`, and the same per-field slots mirror it from
there. The only difference is timing — its error appears when a save fails,
not while the user types.

**Generated forms also hold live errors back until the form is dirty.** A
freshly opened form — especially a blank create form — would otherwise flag
every empty required field before the user has typed anything. So `error_for`
returns live errors only once `dirty?` turns true, at the user's first edit.
Errors mirrored from a failed commit are exempt from this gate: the user
asked for that save, so its errors always show.

**The live checks are a snapshot of the model at scaffold generation time.**
The generator derives the clauses from the validators the model declares,
writes them into the form, and never touches that file again. A validator you
add later works as you would expect, but its live check is missing until you
derive the form again (by running `bin/rails g hibiki:rails:form Book`, which
rewrites only the form and the two form views) or write the clause in by
hand.

## The argument list decides the field order

The argument list is the run of `field:type` pairs after the model's name in
the generator command:

```sh
bin/rails g hibiki:rails:scaffold_controller Book title:string intro:text available:boolean
```

Every generated view renders the fields in the order you name them here —
the command above puts the title first in all generated views.

Run the generator without the pairs, and it falls back to the model's
columns, in the order ActiveRecord reports them (`columns_hash`) — for an
app built from `schema.rb`, that will be alphabetical. A generated form will
then read "Available, Intro, Title" — a form no one would use.

A field you name that the model has no column for is still generated, from
the argument alone, and the post-install output points it out. The choice to
keep it is deliberate: the field may be a column whose migration is still to
come, and a silently dropped field would be the worse failure.

## Read the post-install output

Every notice the generator prints exists because the thing it warns about
fails **silently** — nothing raises, and nothing shows up in the file list.
Each notice opens with a short tag; the sections below take them in turn.

### `restart` — the new directories need a restart

`app/forms/` is almost certainly new to your app, and **Rails computes
autoload paths from the `app/*` glob at boot** — a directory created after
boot is not on the list. Until you restart the server, the new constants
raise `NameError`. This is also why the query object lives in `app/models`
rather than a tidier `app/queries`.

### `css` — rebuild your stylesheet

The generated views introduce classes your stylesheet has never seen, and
Tailwind purges what it cannot find.

### `assoc` — the display label is a guess

Rows print an associated record by a display label, and the generator has to
guess which column that is: it picks the associated model's first string
column — `author.name`, here. If it guessed wrong, edit the generated views;
every place a row prints the label reads it as `book.author&.name`.

### `order` — you can choose the field order

This notice appears when the field order came from the schema and there were
more than two columns to order; it prints the command that would set the
order explicitly. See
[the field order section](#the-argument-list-decides-the-field-order), above.

### `fields` — a field with no column behind it

You named a field the model has no column for. Either the name is misspelled,
or the column's migration is still to come — check the spelling, or migrate
and re-run. The field is generated either way, but knows nothing of the
model; [the field order section](#the-argument-list-decides-the-field-order)
explains why.

### `form` — the form has no live checks

`live_errors` is where the generated form keeps its as-you-type checks,
derived from the model's validators
([covered above](#live-validation-checks-only-what-a-form-can-check)); this
notice means it came out empty. The notice names which of three reasons
applies — the model declares no validators the generator can read, there is
no model yet, or the migration has not run so there was no schema to read
from — and prints the catch-up command to run once
validators exist: `bin/rails g hibiki:rails:form Book`.

### `unique` — a unique index with no validator

**A database constraint is not a validator**, and the generated form can only
mirror what the model checks. Without a matching `validates … uniqueness:`, a
duplicate raises `ActiveRecord::RecordNotUnique` inside the channel instead of
showing a field error. An exception there is a line in the development log,
nothing more — and since the acknowledgement that clears the busy indicator is
sent from an `ensure`, the user sees a round trip that completes cleanly but
saves nothing.

The notice names the column and the exact line to add, for single and
composite indexes alike. The generator deliberately does not write it for you:
a uniqueness validator costs a query on every save, and whether to pay that is
your call.

### `skip` — a column the generator left out

The notice names the column and the reason its shape cannot be a form field —
rich text needs its own editor, a password digest must not travel over the
channel, a polymorphic `belongs_to` has no single collection to select from.
Refusing out loud is the point: a scaffold that dropped the column quietly
would look complete while a field is missing.

### `hint` — the client isn't wired

`hibiki:rails:install` hasn't run, or has been partly undone. Nothing on the
generated page will be live until the install is complete.

## Loading and connection state

All reactivity in this stack is server-side, so every interaction is a round
trip. The JS client records what it knows about that trip as HTML attributes
on the island root and on the control that fired it; the generated app
turns those attributes into something a user can see.

**The mechanism is documented on [the Loading state page]({{ "/loading-state/"
| relative_url }})** — the states, the attributes, the reserved payload key
and the timing knobs. What follows is only what the generator does with it.

`app/assets/stylesheets/hibiki_busy.css` is the app's half of the contract: a
stylesheet that maps the client's attributes onto five sites. It is written
once per app, and the generator wires it in for you.

| Site | What you see |
| --- | --- |
| The counts line in `_controls` | A small spinner beside the sentence. This partial is never re-rendered, which makes it the safest home for an island-level indicator. |
| Above the list | A non-blocking progress bar. The site that needs one most: the page links are real anchors that jump to the list, so by the time a reply lands the reader is already staring at the *old* list, scrolled to the top of it. |
| The infinite-scroll sentinel | The Load-more control *is* the spinner — it already carries the busy attribute, so this costs no markup. |
| Each row's destroy button | Dimmed while its own trip is in flight. |
| The inline-edit Save button | A spinner in the button. |

Four things about that file are worth knowing.

**It is app code, not gem code.** Rewrite it, restyle it, delete sites you
don't want. Nothing in the gem reads it.

**`--css=none` keeps its hooks.** That option means no *styling* class; the
`hbk-*` hooks the loading state needs are structural, not decorative, and stay
in every variant.

**It gets onto the page one of four ways**, and the post-install output tells
you which. A cssbundling or tailwindcss-rails entry stylesheet gets an
`@import`; a layout already using `stylesheet_link_tag :app` or `:all` needs
nothing at all, because Propshaft's bulk helper picks the file up; anything
else gets a `stylesheet_link_tag` injected into the layout. Only when none of
those applies does the generator print the line for you to add — and if you
ignore it the failure is silent, because the file is on disk and simply
nothing links it.

**Its rules sit outside any CSS `@layer` on purpose.** Two of them set
`display` on elements that also carry Tailwind utility classes, and Tailwind
puts its utilities in `@layer utilities`. That contest is decided by
layering: in the cascade, a declaration outside every layer
takes priority over one inside a layer, no matter which stylesheet links first.

Scaffolded before 0.5.0? These rules used to be an inline `<style>` in
`app/views/<resource>/_busy.html.erb`. The post-install output names the file, and you can safely delete it.
{: .note }

**The generated views never branch on a loading flag**. Client-side frameworks render a spinner or a skeleton in the
content's place because, until the data arrives, they have nothing to show.
This stack always has something to show: the initial server-rendered page is
real content, and every update after it swaps valid content for newer valid
content — during a round trip, the list on screen is *stale*, never absent.
So the generated idiom is to mark the stale content as busy — a dimmed
button, a spinner beside the counts — rather than to replace it with a
skeleton.

Two smaller choices are worth keeping if you rewrite the stylesheet. Busy
buttons and links are **dimmed, never disabled**: a disabled element cannot
hold keyboard focus, so disabling the button a keyboard user just pressed
would throw their focus back to the page body — their next Tab starts over
from the top of the page. And text inputs are left entirely alone: the
debounced search fires while the user is still typing, and a field that dims
under their fingers reads as a fault, not as feedback.

## Phlex instead of ERB

`--phlex` emits Phlex components under `app/views/books/*.rb` instead of ERB
templates:

```sh
bin/rails g hibiki:rails:scaffold Book title:string author:references --phlex
```

It needs the `phlex-rails` gem and `bin/rails g phlex:install`, whose
initializer autoloads `app/views` under the `Views` namespace. The generator
warns if either is missing and writes the files anyway, so the scaffold can
come first — but the warning matters: without that initializer every generated
page raises `NameError` on its first request.

Not to be confused with the `hibiki_phlex` gem, which is a different idiom.
There the *component* owns reactive state and a render effect re-renders it.
Here the *channel* owns the state, so these components are ordinary
stateless views that get their locals as keyword arguments. See
[Phlex support]({{ "/phlex-support/" | relative_url }}) for more detail.
{: .note }

**Only the view layer changes.** The channels, the query object, the
`ReactiveForm`, the model injections, every action and the whole
`data-hibiki-*` protocol are identical either way. Outside the templates the
difference is two lines: the controller renders `Views::Books::Index.new(...)`
explicitly at each site, and the channels broadcast `renderable:` instead of
`partial:`.

Naming follows Phlex rather than Rails partials — no leading underscore, no
`.html.erb`, and no `_book`/`_book_form` rename, because a component is
reached by constant:

| ERB | Phlex |
| --- | --- |
| `app/views/books/index.html.erb` | `app/views/books/index.rb` → `Views::Books::Index` |
| `app/views/books/_book.html.erb` | `app/views/books/row.rb` → `Views::Books::Row` |
| `app/views/books/_book_form.html.erb` | `app/views/books/row_form.rb` → `Views::Books::RowForm` |

The strict-locals header becomes a keyword initializer, which is a genuine
upgrade: Ruby enforces it, so a wrong local raises at the call site naming the
argument instead of rendering blank.

Four differences from ERB show up in the generated code and are worth
recognizing, because none of them is a style choice:

- Phlex renders `String`, `Symbol`, `Integer` and `Float` and **raises** on
  anything else, so date, time and decimal columns are emitted with `to_s`.
- Phlex **omits a `false`-valued attribute**, so the page control's
  `data-turbo` is the string `"false"` — as a boolean it would vanish and
  Turbo Drive would take the click back.
- Phlex emits **no whitespace between siblings**, so the components space
  their inline neighbours explicitly. Without that, `Title:` runs into its
  value.
- `options_for_select` outputs directly and raises if its return value is
  passed on, so both select sites take their options from a block.

The one thing you give up is idiomatic Phlex in the full-page form: it is
built on the `form_with` builder rather than hand-rolled elements, which keeps
`form.label` / `form.collection_select` and therefore for/id pairing and the
`min:`/`max:` injection.

## Sorting, and where empty values land

The generated sort is `order(column => direction)` with no `NULLS` clause, and
**that means rows with an empty value land at opposite ends on different
adapters**: SQLite sorts `NULL` first ascending and last descending;
PostgreSQL does the opposite.

This is not a defect and it is not portably fixable. `NULLS LAST` needs SQLite
3.30 or newer, and MySQL has no such syntax at all. If your app targets one
adapter and you want a specific answer, say so explicitly in `book_query.rb` —
the generated code carries a comment at that line for whoever meets it there.
