---
title: Reactive forms
nav_order: 2
---

# Reactive forms

In Hibiki, the values a page reacts to live in *signals*: a `state` holds a
value you can write, a `derived` computes from other signals, and writing a
state notifies everything that read it ([Getting started]({{
"/getting-started/" | relative_url }}) introduces this model). An edit screen
fits that model well once the record's attributes become signals: copy the
attributes in when the form opens, edit and validate through signals while the
user types, and write everything back to the database in one step when the
user saves. The record itself appears only at those two boundaries.

[Working with ActiveRecord]({{ "/working-with-active-record/" | relative_url
}}) builds such a form object by hand and explains why the record stays out of
the signal graph. The hand-written version has one clerical cost: the
attribute list appears three times — once per `state` declaration, once in the
method that copies the record in, and once in the method that writes it back.

`Hibiki::Rails::ReactiveForm` writes those three pieces from one declaration:

```ruby
class TodoForm
  include Hibiki::Rails::ReactiveForm

  reactive_attributes Todo, :title, :done

  derived(:title_error) { "can't be blank" if title.strip.empty? }
  derived(:valid?)      { title_error.nil? }
end
```

`reactive_attributes Todo, :title, :done` declares a `state` for each listed
attribute, a `.from` constructor that copies a record's attributes into those
states (Hibiki calls this *hydrating* the form), and a `#commit` that writes
them back to the record. In use:

```ruby
form = TodoForm.from(Todo.find(id))
form.title = "buy milk"     # an ordinary signal write
form.dirty?                 # => true — something changed since hydration
form.commit                 # saves; returns false if the model is invalid
form.error_for(:title)      # => the model's own message, after a failed commit
```

The states are declared through the core's [`Hibiki::Reactive`]({{
"/class-based-reactivity/" | relative_url }}) macro, so everything that page
covers applies here too: you can compose deriveds over the fields, as
`title_error` and `valid?` do above, and a subclass inherits the declarations.

## The surface

| Method | What it does |
| --- | --- |
| `.from(record)` | Builds a form and hydrates it from the record. This is the only supported constructor. Extra arguments are forwarded to `#initialize`, so a form with its own constructor still works. |
| `#hydrate(record)` | Copies the record's attributes into the signals again. This is also how you reset the form. |
| `#record` | The record the form was hydrated from. |
| `#persisted?` | Delegates to the record, so a view can label the button Create or Update. |
| `#to_h` | The declared attributes and their current values, as a hash. |
| `#dirty?` | A derived that is true when `#to_h` differs from the values hydration copied in. |
| `#commit` | Writes the attributes back with `record.update`. On failure it returns false and copies the model's errors into `#errors`. |
| `#commit!` | Like `#commit`, but raises on failure. |
| `#errors` | The model's errors from the last failed commit, as a hash: `{ title: ["can't be blank"] }`. |
| `#error_for(:title)` | The first message for one field, or nil. |

## Collections

Two more macros extend the same idea beyond flat attributes.

`reactive_association :songs` declares one more signal, `song_ids`, for a
`has_many :through` association. It hydrates from the record's own ids reader
and commits through the association writer, which handles the join-row
bookkeeping. Each id is cast through the *target* model's primary-key type,
because values arriving from the browser are strings. [Multi-select
associations]({{ "/multiselect/" | relative_url }}) covers the macro and the
generator that builds a whole searchable dropdown on top of it.

`reactive_nested :chapters, "ChapterForm"` declares a signal holding an
**array of child forms**, backed by `accepts_nested_attributes_for`. The child
class may itself declare `reactive_nested`, so a whole tree of records edits
in the signal graph and persists in the parent record's one save. [Nested
forms]({{ "/nested-forms/" | relative_url }}) covers the macro, the generic
channel actions that drive it, and the generator that wires one parent→child
edge per run.

## Two layers of validation, on purpose

A reactive form validates twice, and the two layers do different jobs.

The first layer is the error deriveds you write by hand, like `title_error`
above. A derived recomputes whenever a signal it read changes, so these give
**feedback on every keystroke**. They are necessarily hand-picked, like
client-side validation in any other stack — a derived cannot know about a
uniqueness rule without a database query, and shouldn't run one on every
keystroke.

The second layer is the model's own `validates` declarations, which stay
**authoritative at commit**. When `#commit` fails, it copies `record.errors`
into a signal on the form (the docs call this *mirroring*), so every rule the
form didn't re-derive still reaches the same per-field slots — one round trip
later, which is the honest cost of a check that needs the database.

`#error_for` returns the first message for a field. That is exactly the shape
a [reactive value]({{ "/reactive-values/" | relative_url }}) wants, so
streaming a field's error to the browser is one line:

```ruby
transmit_value(:title_error) { @form.error_for(:title) }
```

The mirrored errors are a plain hash rather than the `ActiveModel::Errors`
object. Hibiki drops a write when the new value equals the old one, and a
mutable object that stays live in the model makes that rule murky — the
object in the signal and the object being written can be the same thing. Each
mirror copies the messages into a fresh hash, which compares honestly — and
the hash is what a view wants anyway.

Because each error derived reads only its own field, a keystroke in one field
never recomputes the other fields' checks, and each error area re-renders
independently.

## `commit` and `commit!`

The pair follows Rails' `save` / `save!` convention: `#commit` returns false
and mirrors the errors; `#commit!` raises after mirroring, so the messages are
already in `#errors` by the time you catch the exception.

**Inside a channel action, `#commit` is the one you want.** The signal graph
runs on its own thread, and an unrescued raise there takes the job down — the
action is over, nothing updates, and the user sees a round trip that did
nothing. Returning false instead lets the render effect re-render with the
error messages and the user's values intact:

```ruby
def save(data)
  assign(data)                 # the channel's helper: payload fields → form
  return unless @form.commit   # a false commit already mirrored the errors

  @editing_id.value = nil
  invalidate
end
```

## Wire types are cast for you

Values arriving from the browser through a channel action come in as
**strings** — `"0"`, `"3"`, `"false"` — while the signals want the column's
real type. Every writer the macro generates casts its value through
`Model.type_for_attribute(name).cast(value)` before the signal sees it, which
is the difference between `done = "false"` bugs and not:

```ruby
form.done = "0"        # => false
form.priority = "3"    # => 3
```

The cast wraps the generated writer rather than replacing it, so `#title=` is
still an ordinary signal write, with all the dependency tracking that implies.

## One form serves create and update

Rails' `form_with model:` renders a create or an edit form from the same code,
and a reactive form works the same way — without needing a second path.
`from(Todo.new)` hydrates the new record's column defaults, which beats a
blank constructor because the form never has to re-declare `done: false`. And
`#commit` on an unpersisted record assigns and saves, which is an INSERT.
`#persisted?` flips afterwards, because a successful commit re-hydrates the
form from the record.

That re-hydrate matters for more than `#persisted?`: callbacks and database
defaults may have changed values during the save, and re-reading the record is
the only way the form finds out. Hydration runs inside one `Hibiki.batch`, so
it costs one effect run rather than one per attribute.

`#dirty?` on a create form therefore means "changed from the column defaults",
which is exactly the condition that should enable a Create button.

## Two rules the reactive form keeps

**The record is held in a plain instance variable, never in a signal.** Only
`#hydrate` and `#commit` touch it — the two boundaries. This is the
[ActiveRecord guide]({{ "/working-with-active-record/" | relative_url }})'s
rule unbent: records at the edges, signals in the middle. It is also what
makes create-vs-update invisible to the caller.

**The model may be a Class or a String/Symbol, and is resolved on every use.**

```ruby
reactive_attributes "Todo", :title, :done
```

A form class under `app/` must not hold a constant across a Zeitwerk reload,
so the macro memoizes nothing. Pass the constant if the form lives outside
`app/`; pass the name if it doesn't matter.

## What the generator writes

[CRUD scaffolding]({{ "/crud-scaffolding/" | relative_url }}) emits one of
these per resource, with the attribute list taken from the schema and the live
error clauses derived from the model's own validators:

```ruby
class BookForm
  include Hibiki::Rails::ReactiveForm

  reactive_attributes Book, :title, :intro, :available, :author_id

  derived(:live_errors) do
    {
      title: ("can't be blank" if title.to_s.strip.empty?),
      author_id: ("must be given" if author_id.blank?)
    }.compact
  end

  derived(:valid?) { live_errors.empty? }

  # The record's mirrored errors win once a commit has actually failed.
  def error_for(name) = super || live_errors[name.to_sym]
end
```

Two things are worth reading off that. First, `reactive_attributes` **is** the
strong-params analogue: `#to_h` is what `#commit` assigns and what the channel
iterates when it applies a payload, so a channel action cannot mass-assign
past the declared list. Second, `live_errors` is always *defined*, even when
it starts empty, so `#error_for` and every field's error partial stay
branch-free.

Nothing here is generated more than once. Add validators to the model and run
`bin/rails g hibiki:rails:form Book` to derive the clauses again (it rewrites
only the form and the two form views), or write them in by hand — the file is
yours from the moment it lands.
