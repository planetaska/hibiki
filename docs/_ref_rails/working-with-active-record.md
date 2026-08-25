---
title: Working with ActiveRecord
nav_order: 1
---

# Working with ActiveRecord

In Hibiki, a page updates because a *signal* changed. Writing a `state` value notifies everything that read it: deriveds recompute, and the effect that renders the page runs again ([Getting started]({{ "/getting-started/" | relative_url }}) introduces this model). However, the database is outside that loop. `Todo.update!` changes a row but writes no signal, so nothing is notified and nothing refreshes. Every pattern on this page answers the question that gap raises: **where does the database plug into the signal graph, and who re-syncs?**

The running example is the `TodoList` component from [Phlex support]({{ "/phlex-support/" | relative_url }}), backed by a real `todos` table (with two columns: `title`, `done`).

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

Everything here is view- and transport-agnostic. The same patterns apply to the ERB-partial style: if you are working with ERB or ViewComponent, declare the `state` and `derived` values inside the channel rather than in a component.
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

`ActiveRecord#==` compares class and id only, so a reloaded record equals the stale one even though `done` flipped — and the fresh array `==` the old array. [Writing an `==`-equal value is a no-op by design]({{ "/getting-started/" | relative_url }}): nothing notifies, nothing updates, and no error tells you why.

Since 0.6.0, hibiki_rails catches this exact trap **in development**: when `==` drops a write but the two values' `attributes` differ, a warning naming this page lands in the log. Production behavior is unchanged — the write is still a no-op.
{: .tip }

**Don't read the database from a derived with no signal dependency.**

```ruby
derived(:remaining) { Todo.where(done: false).count }   # recomputes never
```

Deriveds track signals, not SQL. This runs once, caches the count, and returns it forever.

## The Solution

Two rules prevent all three mistakes above, and every pattern below follows both:

1. **Records stop at the boundary.** The boundary is the line where database data enters the signal graph. ActiveRecord objects stay on the Rails side of it; what crosses into a signal is a plain copy — a hash, or a `Data` struct — whose `==` compares actual contents, so a changed row never looks equal to its stale copy.
2. **Every database write is paired with a signal write.** The database cannot announce its own changes, so the code that writes a row must also write a signal — that second write is what tells the graph anything happened. The patterns below differ only in how they arrange this pairing.

## The simplest thing that works: snapshot and write-through

This pattern follows the two rules as literally as possible. Copy the rows into plain values — a *snapshot* of the table — and hold that snapshot in `state`. Then give every method that changes data (every *mutator*) the same two steps: write the database first, then re-assign the state from a fresh snapshot:

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

`Data` objects compare by contents: two rows are `==` only when every field matches. So the array assigned after a toggle genuinely differs from the one it replaces, and the render effect re-runs. This works, and for a small page it's fine.

The cost is the discipline it demands: every mutator must remember its `self.items = fetch`. Forget one and you're back to the first mistake above — the page silently goes stale, and nothing catches it. The next pattern removes that class of bug.

## An opt-in upgrade: comparing records by attributes

Writing a `Row` struct for every model is ceremony and can become tedious very quickly. Since hibiki 0.3 there is a shortcut: a signal can take an `equals:` option that replaces `==` with a comparison of your choice. Pass `Hibiki::Rails.record_equals` and the signal can hold the records themselves — **frozen**, so the mistakes a comparison cannot catch raise instead of going stale:

```ruby
# Instead of a Data struct, :items here is a real ActiveRecord object
state(:items, equals: Hibiki::Rails.record_equals) { fetch }

private

# Fetches and freezes the snapshot — see below
def fetch = Todo.order(:id).strict_loading.map { it.readonly!; it.freeze }
```

`record_equals` fixes the dishonest `==` problem from *What not to do*: it compares records by class and `attributes`, recurses through arrays, and falls back to `==` for everything else. A re-assignment after a toggle now genuinely differs, and the page updates — with no `Row` struct to maintain. It must be the signal's `equals:` rather than a check you run by hand, because hibiki compares values in two places — once when you assign (the write gate), and again when a batch flush asks whether an effect's sources changed — and both use the signal's comparator.

Freezing handles the other problem: no comparison can catch a record mutated in place, so the fetch makes mutation impossible. `#freeze` makes an attribute write raise, `readonly!` makes `save` raise, and `strict_loading` makes an unpreloaded association walk raise — each mistake turns from a silently stale page into an exception.

This is a shortcut for the snapshot pattern, not a license to put live records in signals — the two rules above still hold. A comparator only sees values that pass through a signal write, and it syncs nothing another writer changed. It is also what the [scaffold]({{ "/crud-scaffolding/" | relative_url }}) generates for its `rows`.

## Better solution: a version signal and a lazy derived query

The snapshot pattern keeps a copy of the data in state and refills it after every write. This pattern inverts the relationship: state no longer holds data at all. Instead, it holds a counter — an **invalidation token** — whose only job is to record that the table changed, and a derived runs the query. Because the derived reads the counter before querying, the counter becomes its tracked dependency: bump it, and the next render re-runs the query:

```ruby
state :db_version, 0 # the invalidation token

derived(:items) do
  db_version   # the tracked dependency — the query re-runs when it bumps
  Todo.order(:id).map { |t| Row.new(id: t.id, title: t.title, done: t.done) }
end
derived(:remaining) { items.count { |row| !row.done } }

# Bumps the token version
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

- **The database stays the single source of truth.** The graph holds only an integer; the derived re-reads the table whenever that integer says something changed. There is no cached copy to drift out of date.
- **Mutators can't forget.** Each one shrinks to two steps that never vary: write the database, call `invalidate`. There is no per-mutator fetch logic to get wrong.
- **Bursts collapse into one query.** A derived recomputes when it is read, not when it is written, and every channel action runs inside one `Hibiki.batch` — so an action that creates three rows and bumps the counter three times still triggers one re-render, and therefore one query.
- **Anything can trigger a re-sync.** Whatever learns the table changed only has to call `invalidate`, be it the channel's own actions here, or later on this page, controllers, jobs, and other users' writes.

## Editing one record: a reactive form object

The patterns above sync a list; an edit screen has a different story. It works on one record's fields, and most of what happens there — typing, validating — should touch nothing but signals until the user saves. So copy the record's attributes into signals when the form opens (*hydrate*), let deriveds handle validation while the user edits, and write the attributes back in one step on save (*commit*). ActiveRecord appears only at those two moments:

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

Every keystroke writes `title`; `valid?` and `error` re-derive; the `transmit_value` line streams the fresh error text to the browser as a [reactive value]({{ "/reactive-values/" | relative_url }}). The database sees nothing until `save`. Unsaved edits, dirty checking, and cross-field validation all become ordinary deriveds over the form's signals.

That form object is worth writing by hand once, because it is the shape everything else here builds on. After that, `Hibiki::Rails::ReactiveForm` writes it for you: `reactive_attributes Todo, :title, :done` generates the states, the `from` hydrator, and the `commit!` writer, then adds everything the hand-written version lacks for a real-world reactive form — incoming values cast to each column's type, dirty tracking, and the model's own validation errors mirrored into per-field live updates. See [Reactive forms]({{ "/reactive-forms/" | relative_url }}).

## Other writers: bridging `after_commit` into the graph

Everything so far assumed the channel's own actions are the only writers. They rarely are — most writes in a Rails app happen in a controller action, and the rest come from background jobs, other users' channels, or the console. The graph can't see any of those, so something has to carry "this table changed" from wherever the write happened to every live graph that cares.

The carrier is a bridge with two halves: the model announces every change, and each channel listens for the announcement. The model's half is a broadcast that carries nothing — no payload, no HTML, just the fact that something changed (a *ping*). Here we hook it to `after_commit` (instead of `after_save`), so subscribers re-query only after the data is actually visible:

```ruby
class Todo < ApplicationRecord
  after_commit { ActionCable.server.broadcast("todos:changed", {}) }
end
```

The channel's half subscribes to the ping. One rule here you must not skip: ActionCable delivers the message on one of its own worker threads, while the channel's signals all live on a single dedicated thread of their own (see [Channel lifecycle]({{ "/channel-lifecycle/" | relative_url }})). **Only that thread may touch a signal** — so the callback body never writes one directly; it hands the write to the graph's thread with `graph_actor.post`:

```ruby
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel
  # build_graph / add / toggle as above
  
  private # ← keep lifecycle hooks private; see the note below

  def subscribed
    super                              # builds the graph (or rejects)
    return if subscription_rejected?

    stream_from "todos:changed" do |_message|
      # Delivered on a cable thread — hop to the graph thread first.
      graph_actor&.post { Hibiki.batch { @list.invalidate } }
    end
  end
end
```

Now a row created in the console, a job, or another user's tab bumps `db_version` in every subscribed graph; each graph re-queries once, and each connected page updates. That is all you need for a multi-user story: the ping spreads only the news that something changed, and each graph fetches its own data in response.

**Keep `subscribed` private.** ActionCable builds a channel's client-invocable actions from *the public methods the class adds*, and its own `subscribed`/`unsubscribed` are private on the base class — so a **public** override here is a method a client can `perform` by name, which would build a second graph on the connection. Since 0.3.0, hibiki_rails subtracts both hooks (and `build_graph`) from `action_methods`, so this is belt and braces — but write them private anyway; the habit protects the methods it does *not* know about.

Two refinements worth knowing:

- **One invalidation path, if you prefer.** With the bridge in place, the channel's own actions get invalidated twice — once by their explicit `invalidate`, once by the ping (a harmless extra re-render). You can instead drop `invalidate` from the mutators entirely and let the `after_commit` ping be the *only* invalidation path — self-writes and other-writes become indistinguishable, at the cost of a pubsub round-trip of latency on your own actions.
- **Bursts of pings.** A burst of commits means a burst of pings, and each subscriber re-queries per ping. If that ever hurts, debounce at the render effect (`Hibiki::Phlex.render_effect(@list, scheduler: ...)` — see [Phlex support]({{ "/phlex-support/" | relative_url }})) rather than trying to merge the pings themselves.

## Writes from controllers and jobs

The `after_commit` bridge from the previous section deliberately does not care who did the writing. `after_commit` fires no matter where the record was saved, so `Todo.create!` in `TodosController#create`, in a background job, or in `bin/rails console` all reach every subscribed graph — without the writer knowing hibiki exists. A controller has nothing to notify and no channel to reach for: it writes the database, the model pings, the graphs re-query. This is also why the ping carries no payload: it says *the table changed*, not *here is what changed*, so a writer has nothing to assemble.

Four things break that story in practice. Three are ActiveRecord and ActionCable facts rather than hibiki ones, but they all surface the same way — the write lands, the page doesn't move — so they're worth knowing before you go looking for the bug in your graph.

**1. Bulk writes skip the callback.** `update_all`, `delete_all`, `insert_all`, `upsert_all`, `update_column`/`update_columns`, `touch_all`, and raw SQL never run `after_commit` — and those are exactly what a job reaches for. Ping explicitly when you use them:

```ruby
class ArchiveDoneTodos < ApplicationJob
  def perform
    Todo.where(done: true).update_all(archived: true)
    ActionCable.server.broadcast("todos:changed", {})   # update_all ran no callbacks
  end
end
```

**2. The `async` cable adapter doesn't cross processes.** It delivers broadcasts only inside the process that sent them, and it is the Rails default in development:

```yaml
# config/cable.yml
development:
  adapter: async   # in-process only
```
{: data-title="config/cable.yml"}

A controller's ping still works — the web process owns both the writer and the graphs — and so does a job's, as long as jobs run in-process. Move the worker to its own process and that same ping goes nowhere, with no error on either side. Use `solid_cable` or `redis` as soon as anything writes from outside the web process.

**3. `after_commit` fires per record.** A job that saves 500 rows sends 500 pings, and every subscriber re-queries once per ping. Suppress the per-record ping for that path and send one at the end of the batch instead — the job knows where its batch ends, and the render-effect debounce above can only guess. A thread-local flag is enough, because `after_commit` runs on the same thread as the job:

```ruby
class Todo < ApplicationRecord
  after_commit do
    ActionCable.server.broadcast("todos:changed", {}) unless Thread.current[:todos_quiet]
  end
end

class ImportTodos < ApplicationJob
  def perform(rows)
    Thread.current[:todos_quiet] = true
    rows.each { |attrs| Todo.create!(attrs) }           # 500 saves, zero pings
    ActionCable.server.broadcast("todos:changed", {})   # one ping for the whole batch
  ensure
    Thread.current[:todos_quiet] = nil
  end
end
```

**4. A global stream name wakes everyone.** `"todos:changed"` makes every subscriber re-query on every write to the table, including subscribers whose query could never return the row that changed — for example, another account's todos. Scope the stream name to whatever scopes the query:

```ruby
class Todo < ApplicationRecord
  belongs_to :account

  after_commit { ActionCable.server.broadcast("account:#{account_id}:todos", {}) }
end
```

```ruby
private

def subscribed
  super
  return if subscription_rejected?

  stream_from "account:#{current_user.account_id}:todos" do |_message|
    graph_actor&.post { Hibiki.batch { @list.invalidate } }
  end
end
```

Build the stream name from the connection's identity, as above — never from a parameter the client sends, or a client could subscribe to another account's stream. With these empty pings the damage would be minimal: a subscriber learns only *when* another account writes and not what it writes. But scope it correctly anyway — the next thing you put on a stream may carry real data.
{: .warning }

Finally, the broadcast call now appears in several places: the model's callback and every job that writes in bulk. Give it one home that all of them share — which also keeps ActionCable out of the model:

```ruby
module TodoChanges
  def self.notify = ActionCable.server.broadcast("todos:changed", {})
end

class Todo < ApplicationRecord
  after_commit { TodoChanges.notify }
end
```

You could instead call `TodoChanges.notify` from each controller action and drop the model callback. That works, but it re-creates the snapshot pattern's weakness at a new layer: every writer has to remember the ping, and the one that forgets fails silently. Our suggesion is to keep the ping on the model, where no write can slip past it.

## Choosing the right pattern

| Pattern | Reach for it when |
|---|---|
| Snapshot + write-through | A small page, a first pass — accept the per-mutator re-fetch discipline |
| Version signal + lazy derived query | The default for anything list-shaped |
| [Reactive form object]({{ "/reactive-forms/" | relative_url }}) | Editing a single record; live validation and dirty state |
| `after_commit` bridge | Rows change outside the channel's own actions — controllers, jobs, other users |

The patterns are not rivals — a full page usually runs them together. The version signal keeps the list in sync, a form object handles the record being edited, and the bridge lets in the writes the current channel didn't make. Underneath all three, the two rules from the top never bend: records stop at the boundary, and every database write pairs with a signal write.

For a standard CRUD resource, you don't have to assemble this by hand. [`hibiki:rails:scaffold`]({{ "/crud-scaffolding/" | relative_url }}) generates all three patterns at once: the version signal, the form object, and the `after_commit` bridge. The generated rows cross the boundary as frozen snapshots, as in the opt-in upgrade above. Reading the generated channel beside this page is a good way to see the patterns composed, and to get a feel for what a real-world application looks like.
