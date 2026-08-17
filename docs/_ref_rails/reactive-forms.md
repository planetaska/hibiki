---
title: Reactive forms
nav_order: 2
---

# Reactive forms

An edit screen wants a record's attributes as *signals*: hydrate them at one
edge, work reactively in the middle, commit back at the other, so ActiveRecord
only ever appears at the two boundaries. [Working with ActiveRecord]({{
"/working-with-active-record/" | relative_url }}) shows that shape written by
hand — and written by hand it repeats the attribute list three times, once per
`state`, once in the hydrator, once in the writer.

`Hibiki::Rails::ReactiveForm` is the macro that writes those three for you:

```ruby
class TodoForm
  include Hibiki::Rails::ReactiveForm

  reactive_attributes Todo, :title, :done

  derived(:title_error) { "can't be blank" if title.strip.empty? }
  derived(:valid?)      { title_error.nil? }
end
```

```ruby
form = TodoForm.from(Todo.find(id))
form.title = "buy milk"     # a plain signal write
form.dirty?                 # => true
form.commit                 # => false if invalid
form.error_for(:title)      # => the model's own message
```

`reactive_attributes` declares one `state` per attribute through the core's
[`Hibiki::Reactive`]({{ "/class-based-reactivity/" | relative_url }}) macro, so
everything you already know about class-based reactivity applies — including
composing deriveds over the fields, and inheriting declarations in a subclass.

## The surface

| Method | What it does |
| --- | --- |
| `.from(record)` | The only supported constructor: build, then hydrate. Extra arguments are forwarded to `#initialize`, so a form with its own constructor still works. |
| `#hydrate(record)` | Re-hydrate from a record — also the reset path |
| `#record` | The held record |
| `#persisted?` | Passthrough, so a view can label the button Create or Update |
| `#to_h` | The declared attributes, as they stand |
| `#dirty?` | A derived: `to_h` differs from the hydrated snapshot |
| `#commit` | `record.update(**to_h)`. False plus mirrored errors on failure. |
| `#commit!` | The raising half |
| `#errors` | `{ title: ["can't be blank"] }` |
| `#error_for(:title)` | The first message, or nil |

## Collections

`reactive_association :songs` declares one more signal — `song_ids`, over a
`has_many :through` — hydrated from the record's own ids reader and committed
through the association writer, which does the join-row bookkeeping. Each id
is cast through the *target* model's primary-key type, since channel payloads
arrive as strings. [Multi-select associations]({{ "/multiselect/" |
relative_url }}) covers the macro and the generator that builds a whole
searchable dropdown on top of it.

`reactive_nested :chapters, "ChapterForm"` declares a signal holding an
**array of child forms** over `accepts_nested_attributes_for` — the child
class may itself declare `reactive_nested`, so a whole tree edits in the
graph and persists in the record's one save. [Nested forms]({{
"/nested-forms/" | relative_url }}) covers the macro, the generic channel
actions that drive it, and the generator that wires one parent→child edge
per run.

## Two layers of validation, on purpose

Hand-written error deriveds give **per-keystroke feedback**. They are
necessarily hand-picked, like client-side validation in any other stack — a
derived cannot know about a uniqueness rule without a query, and shouldn't run
one on every keystroke.

The model's own `validates` stay **authoritative at commit**. When `#commit`
fails it mirrors `record.errors` into a signal, so everything the form didn't
re-derive still reaches the same per-field slots — one round trip later, which
is the honest cost of a check that needs the database.

`#error_for` returns the first message for a field, which is the shape that drops
straight into a [reactive value]({{ "/reactive-values/" | relative_url }}):

```ruby
transmit_value(:title_error) { @form.error_for(:title) }
```

Errors are a plain hash signal rather than the `ActiveModel::Errors` object.
A mutable object in a signal makes hibiki's "writing an equal value is a no-op"
rule murky, and the hash is what a view wants anyway.

Because each error derived reads only its own field, a keystroke in one field
never recomputes the others' checks, and each error area repaints
independently.

## `commit` and `commit!`

Rails' `save` / `save!` convention. `#commit` returns false and mirrors the
errors; `#commit!` raises after mirroring, so the messages are already in
`#errors` by the time you catch it.

**Inside a channel action, `#commit` is the one you want.** The graph runs on its
own thread, and a raise there takes the job down — the action is over, nothing
repaints, and the user sees a round trip that did nothing. Returning false lets
the render effect repaint with the messages and the user's values intact:

```ruby
def save(data)
  assign(data)
  return unless @form.commit   # a false commit already mirrored the errors

  @editing_id.value = nil
  invalidate
end
```

## Wire types are cast for you

Channel action payloads arrive as **strings**. Every generated writer casts
through `Model.type_for_attribute(name).cast(value)` before it reaches the
signal, which is the difference between `done = "false"` bugs and not:

```ruby
form.done = "0"        # => false
form.priority = "3"    # => 3
```

The cast wraps the writer rather than replacing it, so `#title=` is still an
ordinary signal write with all the tracking that implies.

## One form serves create and update

The `form_with model:` convention, and it falls out of the surface rather than
needing a second path. `from(Todo.new)` hydrates the column defaults — better
than a blank constructor, because the form never has to re-declare
`done: false` — and `#commit` on an unpersisted record assigns and saves, i.e.
an INSERT. `#persisted?` flips afterwards, because a successful commit
re-hydrates from the record.

That re-hydrate matters for more than `persisted?`: callbacks and database
defaults may have moved values, and hydration runs inside one `Hibiki.batch`, so
it costs one effect run rather than one per attribute.

`#dirty?` on a create form therefore means "changed from the defaults", which is
exactly what should enable a Create button.

## Two rules it keeps

**The record is held in a plain ivar, never in a signal.** It is touched only by
`#hydrate` and `#commit` — the two boundaries. This is the AR guide's rule
unbent: records at the edges, signals in the middle. It is also what makes
create-vs-update invisible to the caller.

**The model may be a Class or a String/Symbol, and is resolved on every use.**

```ruby
reactive_attributes "Todo", :title, :done
```

A form class under `app/` must not pin a constant across a Zeitwerk reload, so
nothing is memoized. Pass the constant if the form lives outside `app/`; pass the
name if it doesn't matter.

## What the generator writes

[CRUD scaffolding]({{ "/crud-scaffolding/" | relative_url }}) emits one of these
per resource, with the attribute list taken from the schema and the live error
clauses derived from the model's own validators:

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

Two things to read off that. `reactive_attributes` **is** the strong-params
analogue — `#to_h` is what `#commit` assigns and what the channel iterates when
it applies a payload, so a channel action cannot mass-assign past the list.
And `live_errors` is always *defined*, even when it starts empty, so
`#error_for` and every field's error partial stay branch-free.

Nothing there is generated more than once. Add validators to the model and run
`bin/rails g hibiki:rails:form Book` to derive the clauses again (it rewrites
only the form and the two form views), or write them in by hand — the file is
yours from the moment it lands.
