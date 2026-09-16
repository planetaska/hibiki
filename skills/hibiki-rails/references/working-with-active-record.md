# Working with ActiveRecord

The database is outside the signal loop: `Todo.update!` changes a row but
writes no signal, so nothing re-renders. Every pattern answers "where does the
database plug into the graph, and who re-syncs?" With ERB, declare the `state`/`derived` in the channel.

## What not to do

| Shape | Why it fails |
| --- | --- |
| `state(:todos) { Todo.order(:id).to_a }` then `todo.update!(...)` on a member | in-place change; no signal written, nothing notifies |
| `self.todos = Todo.order(:id).to_a` after a reload | AR `==` is class + id, so the fresh array equals the stale one and the write is a no-op; development logs `[hibiki_rails] State write dropped by == although attributes differ` |
| `derived(:remaining) { Todo.where(done: false).count }` | deriveds track signals, not SQL; this computes once and caches forever |

## The two rules

1. Records stop at the boundary: a signal holds a plain copy (a hash or
   `Data`) whose `==` compares contents, or a frozen record behind
   `equals: Hibiki::Rails.record_equals`.
2. Every database write pairs with a signal write; the database cannot announce its own changes.

## Patterns, ranked

| Pattern | Reach for it when |
| --- | --- |
| version signal + lazy derived query | the default for anything list-shaped |
| `record_equals` + frozen rows | the snapshot pattern without a `Row` struct per model; what the scaffold generates |
| snapshot + write-through | a small page, a first pass |
| reactive form object (`hibiki-rails-forms`) | editing one record, live validation, dirty state |
| `after_commit` bridge | rows change outside the channel's actions (controllers, jobs, other users) |

The snippets use the `Hibiki::Reactive` macros, so they belong in a reactive
object the channel holds (`@list = TodoList.new` in `build_graph`, actions
delegating to it). `build_graph` has no `state` or `derived` macro: there,
write `@db_version = Hibiki::State.new(0)` and
`@items = Hibiki::Derived.new { @db_version.value; ... }`, and bump with
`@db_version.value += 1` in the action.

Version signal + lazy derived (the database stays the source of truth, mutators
cannot forget, and bursts collapse into one query since a derived recomputes on read):

```ruby
class TodoList
  include Hibiki::Reactive

  state :db_version, 0                          # the invalidation token
  derived(:items) do
    db_version                                  # tracked; the query re-runs when it bumps
    Todo.order(:id).map { |t| Row.new(id: t.id, title: t.title, done: t.done) }
  end

  def invalidate = self.db_version += 1
  def toggle(id) = (Todo.find(id).toggle!(:done); invalidate)
end
```

`record_equals` + frozen rows (hibiki 0.3 `equals:`; compares class +
`attributes`, recursing through arrays, falling back to `==`; it must be the
signal's comparator because both the write gate and the flush gate use it):

```ruby
state(:items, equals: Hibiki::Rails.record_equals) { fetch }

private

def fetch = Todo.order(:id).strict_loading.map { it.readonly!; it.freeze }
# freeze: attribute writes raise; readonly!: save raises; strict_loading: lazy loads raise
```

Snapshot + write-through: `Row = Data.define(:id, :title, :done)`,
`state(:items) { fetch }`, `self.items = fetch` at the end of every mutator;
forget one and the page goes stale with nothing to catch it.

## The `after_commit` bridge

```ruby
class Todo < ApplicationRecord
  after_commit { ActionCable.server.broadcast("todos:changed", {}) }   # a payload-less ping
end
```

```ruby
private   # keep lifecycle hooks private

def subscribed
  super
  return if subscription_rejected?

  stream_from "todos:changed" do |_message|
    graph_actor&.post { Hibiki.batch { @list.invalidate } }   # cable thread: hop to the graph thread
  end
end
```

The callback never touches a signal directly: ActionCable delivers on a worker
thread and only the graph thread may. You may drop `invalidate` from the
mutators and let the ping be the only path, at the cost of a pubsub hop; for
bursts of pings, debounce at the render effect (`scheduler:`), not the pings.

## Writes from controllers and jobs

`after_commit` fires wherever the save happens (controller, job, console), so
every writer reaches every live graph without knowing hibiki exists. Four things break that:

1. Bulk writes skip callbacks: `update_all`, `delete_all`, `insert_all`,
   `upsert_all`, `update_column(s)`, `touch_all`, raw SQL. Broadcast the ping
   yourself after them.
2. The `async` cable adapter (the development default) delivers only inside
   the sending process, so a separate worker process pings into nothing with
   no error. Use `solid_cable` or `redis` once anything writes from outside.
3. `after_commit` fires per record: 500 saves, 500 pings, 500 re-queries per
   subscriber. Quiet it with a thread-local (`Thread.current[:todos_quiet]`)
   during the batch and ping once at the end.
4. A global stream name wakes every subscriber. Scope it to what scopes the
   query (`"account:#{account_id}:todos"`), built from the connection's
   identity on the channel side, never from a client param.

Give the ping one home (`TodoChanges.notify`) called from the model callback and
the bulk jobs; on the model, no writer can forget it. `hibiki-rails-scaffold` generates all of this.

Full docs: https://planetaska.github.io/hibiki/working-with-active-record/
