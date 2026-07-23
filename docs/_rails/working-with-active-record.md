---
title: Working with ActiveRecord
nav_order: 8
---

# Working with ActiveRecord

Signals track reads of *signals* — the database is outside the graph. `Todo.update!` notifies no subscribers, and no effect re-runs because a row changed. So every pattern on this page is an answer to the same question: **where does the database plug into the graph, and who re-syncs?**

The running example is the `TodoList` component from [Phlex support]({{ "/phlex-support/" | relative_url }}), backed by a real `todos` table (`title`, `done`) instead of an in-memory array.

```ruby
class TodoList < Phlex::HTML
  include Hibiki::Reactive
  include Hibiki::Phlex::Rerenderable

  state(:items) { [] }
  derived(:remaining) { items.count { |item| !item[:done] } }

  def view_template
    div(id: "todos") do
      h2 { "Todos — #{remaining} remaining" }
      ul { items.each { |item| li { item[:title] } } }
    end
  end

  def add(title) = self.items = items + [{ title:, done: false }]
end
```
{: data-title="The TodoList we will be working on"}

Everything here is view- and transport-agnostic — the same patterns apply to the ERB-partial style, with the channel holding the signals instead of a component.
In other words: if you are working with ERB/ViewComponent partials, you should define `state, derived, etc...` inside the Channel file.
{: .tip }

## What not to do

Three tempting shapes, each broken in its own way.

**Don't mutate live records held in a signal.**

```ruby
state(:todos) { Todo.order(:id).to_a }   # looks reasonable…

def toggle(id)
  todo = todos.find { |t| t.id == id }
  todo.update!(done: !todo.done)          # the database changed; the graph saw nothing
end
```

No signal was written, so nothing re-renders. Signals notify on *assignment*, never on in-place mutation of the value they hold.

**Don't re-assign reloaded records either.** The "fixed" version fails more sneakily:

```ruby
def toggle(id)
  Todo.find(id).toggle!(:done)
  self.todos = Todo.order(:id).to_a       # a silent no-op!
end
```

`ActiveRecord#==` compares class and id only — a reloaded record equals the stale one even though `done` flipped, so the fresh array `==` the old array, and [writing an `==`-equal value is a no-op by design]({{ "/getting-started/" | relative_url }}). Nothing notifies, nothing repaints, and there's no error to tell you why.

**Don't read the database from a derived with no signal dependency.**

```ruby
derived(:remaining) { Todo.where(done: false).count }   # recomputes never
```

Deriveds track signals, not SQL. This runs once, caches the count, and returns it forever.

Two rules fall out, and every pattern below follows both:

1. **Records stop at the boundary.** Signals hold plain values — hashes, `Data` structs — whose `==` is honest.
2. **Every database write is paired with a signal write.** The pairing is what the rest of this page is about.

## The simplest thing that works: snapshot and write-through

Project rows into plain values, keep the snapshot in state, and make every mutator write the database first, then re-assign:

```ruby
class TodoList < Phlex::HTML
  include Hibiki::Reactive
  include Hibiki::Phlex::Rerenderable
  include Hibiki::Rails::Helpers

  Row = Data.define(:id, :title, :done)

  state(:items) { fetch }
  derived(:remaining) { items.count { |row| !row.done } }

  def view_template
    div(id: "todos") do
      h2 { "Todos — #{remaining} remaining" }
      ul do
        items.each do |row|
          li do
            button(**on(:toggle, with: { id: row.id })) { row.done ? "☑" : "☐" }
            span { " #{row.title}" }
          end
        end
      end
    end
  end

  def add(title)
    Todo.create!(title:)
    self.items = fetch # Assignment -> triggers update
  end

  def toggle(id)
    Todo.find(id).toggle!(:done)
    self.items = fetch # Assignment -> triggers update
  end

  private

  def fetch = Todo.order(:id).map { |t| Row.new(id: t.id, title: t.title, done: t.done) }
end
```

`Data` rows compare structurally, so the re-assignment after a toggle genuinely differs and the render effect re-runs. This works, and for a small page it's fine.

The deficiency is the discipline it demands: every mutator must remember its `self.items = fetch`. Forget one and you're back to the silent-stale-UI failure above — with nothing to catch it. The next pattern removes that class of bug.

## Better solution: a version signal and a lazy derived query

Invert the relationship. Instead of caching data in state and refilling it, hold an **invalidation token** and let a derived own the query:

```ruby
state :db_version, 0 # a temporary token

derived(:items) do
  db_version   # the tracked dependency — the query re-runs when it bumps
  Todo.order(:id).map { |t| Row.new(id: t.id, title: t.title, done: t.done) }
end
derived(:remaining) { items.count { |row| !row.done } }

def invalidate = self.db_version += 1

def add(title)
  Todo.create!(title:)
  invalidate
end

def toggle(id)
  Todo.find(id).toggle!(:done)
  invalidate
end
```

The view and channel don't change at all:

```ruby
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @list = TodoList.new
    Hibiki::Phlex.render_effect(@list) do |html|
      broadcast_replace target: "todos", html:
    end
  end

  def add(data)    = @list.add(data["title"])
  def toggle(data) = @list.toggle(data["id"])
end
```

Why this is the recommended default for lists:

- **The database stays the single source of truth.** The graph holds an integer; the derived re-reads reality whenever the integer says reality moved. There is no cached copy to drift.
- **Mutators can't forget.** They shrink to "write the database, `invalidate`" — one line of sync instead of per-mutator fetch logic, and the same line no matter what changed.
- **Laziness does the batching.** Deriveds recompute on read, not on write, and every channel action already runs inside one `Hibiki.batch` — so an action that creates three rows and bumps three times still triggers one re-render and therefore **one query**.
- **It composes.** *Anything* that learns the table changed can call `invalidate` — the channel's own actions today, other writers below.

## Editing one record: a reactive form object

List snapshots are the wrong grain for an edit screen. There, hydrate the record's attributes into signals at one edge, work reactively in the middle, and commit back at the other edge — ActiveRecord only ever appears at the two boundaries:

```ruby
class TodoForm
  include Hibiki::Reactive

  state :title, ""
  state :done, false

  derived(:valid?) { !title.strip.empty? }
  derived(:error)  { valid? ? nil : "title can't be blank" }

  def self.from(record)
    new.tap do |form|
      form.title = record.title
      form.done  = record.done
    end
  end

  def commit!(record) = record.update!(title:, done:)
end
```

```ruby
class TodoEditChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @todo = Todo.find(params[:id])
    @form = TodoForm.from(@todo)
    transmit_value(:error) { @form.error.to_s }
  end

  def set_title(data) = @form.title = data["title"]
  def save(_data)     = @form.commit!(@todo) if @form.valid?
end
```

Every keystroke writes `title`, `valid?` and `error` re-derive, and the [reactive value]({{ "/reactive-values/" | relative_url }}) repaints the error live — no round-trip to the database until `save`. Unsaved edits, dirty checking, and cross-field validation all become ordinary deriveds over the form's signals.

## Other writers: bridging `after_commit` into the graph

Everything so far assumed the channel's own actions are the only writers. They aren't — another user, a background job, the console. The graph can't see those writes either, so something has to carry "this table changed" from wherever the write happened to every live graph that cares.

The model's half is a plain ping — no payload, no HTML, just the fact of change. `after_commit`, not `after_save`, so subscribers re-query only after the data is actually visible:

```ruby
class Todo < ApplicationRecord
  after_commit { ActionCable.server.broadcast("todos:changed", {}) }
end
```

The channel's half subscribes to the ping — and here is the one rule you must not skip: **the callback runs on a cable thread, and the graph is confined to its own thread** (see [Channel lifecycle]({{ "/channel-lifecycle/" | relative_url }})). Never touch a signal in the callback body; post onto the graph thread and write there:

```ruby
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def subscribed
    super                              # builds the graph (or rejects)
    return if subscription_rejected?

    stream_from "todos:changed" do |_message|
      # Delivered on a cable thread — hop to the graph thread first.
      graph_actor&.post { Hibiki.batch { @list.invalidate } }
    end
  end

  # build_graph / add / toggle as above
end
```

Now a row created in the console, a job, or another user's tab bumps `db_version` in every subscribed graph, each re-queries once, and each connected page repaints. That's the whole multi-user story: the ping fans out the *invalidation*, and each graph's lazy derived fans in the *data*.

Two refinements worth knowing:

- **One invalidation path, if you prefer.** With the bridge in place, the channel's own actions get invalidated twice — once by their explicit `invalidate`, once by the ping (a harmless extra re-render). You can instead drop `invalidate` from the mutators entirely and let the `after_commit` ping be the *only* invalidation path — self-writes and other-writes become indistinguishable, at the cost of a pubsub round-trip of latency on your own actions.
- **Storminess.** A burst of commits means a burst of pings, and each subscriber re-queries per ping. If that ever hurts, debounce at the render effect (`Hibiki::Phlex.render_effect(@list, scheduler: ...)` — see [Phlex support]({{ "/phlex-support/" | relative_url }})) rather than trying to coalesce the pings themselves.

## Choosing the right pattern

| Pattern | Reach for it when |
|---|---|
| Snapshot + write-through | A small page, a first pass — accept the per-mutator re-fetch discipline |
| Version signal + lazy derived query | The default for anything list-shaped |
| Reactive form object | Editing a single record; live validation and dirty state |
| `after_commit` bridge | Rows change outside the channel's own actions |

The version-signal pattern is the backbone; the form object sits beside it for edit screens, and the bridge layers on top when there are other writers. And whichever you pick, the two boundary rules never bend: records stop at the boundary, and every database write is paired with a signal write.
