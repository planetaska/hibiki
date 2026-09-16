# Channel lifecycle

One subscription, from open to close, and what `include
Hibiki::Rails::Channel` does at each step.

| Moment | What happens |
| --- | --- |
| subscribe | `subscribed` calls `super`, rejects if `cid.blank?`, builds a `Hibiki::Rails::GraphActor` (`build_graph_actor`), posts `Hibiki.root { build_graph }` to it, registers with the registry |
| action | `perform_action` deletes the reserved `hbk` key, posts `Hibiki.batch { super(data) }` to the actor, then `transmit({ ack: seq })` in an `ensure`; a post that fails (no actor, or closed queue) acks `{ ack: seq, dropped: true }` at once |
| unsubscribe | `unsubscribed` unregisters, posts the root's `dispose`, then `stop`s the actor: the queue closes rather than empties, so already-posted jobs drain, `on_cleanup` blocks run, subscriptions drop, the thread exits |
| dev reload | the engine's `to_prepare` hook calls `Hibiki::Rails.registry.dispose_all`, closing every connection with a live channel; clients reconnect and `build_graph` runs on fresh classes |

One thread per graph: ActionCable dispatches on a pool with no per-channel
ordering, and the core has no locks. `GraphActor` gives each subscription a
worker thread (`Thread` named `hibiki-<channel_name>`, 15 chars max); cable
threads only `post` closures, which run one at a time in arrival order.
`post` returns `false` once stopped instead of raising, so a click that races
navigation is dropped quietly.

Every job is one unit of work inside `Rails.application.executor`: autoload
is safe, each job gets a fresh AR query cache, and
`ActiveSupport::CurrentAttributes` reset between jobs. Nothing set on a cable
thread reaches the graph thread. Derive context at the point of use from the
connection's `identified_by`:

```ruby
def archive(data)
  current_user.todos.find(data["id"]).update!(archived: true)   # Current.user was reset
  @todos.value = current_user.todos.map(&:attributes)           # copies, not records
end
```

`rescue_from` handlers run as usual, on the graph thread; unhandled errors go
to the actor's `on_error` (default: `Rails.error`, source `"hibiki_rails"`).

Overriding the hooks:

- `subscribed` and `unsubscribed` overrides must call `super`: skipping it
  leaves no graph, or leaks a thread per closed tab.
- Keep them private. `HIDDEN_ACTIONS = %w[build_graph subscribed unsubscribed]`
  is subtracted from `action_methods`, so a public override is not
  client-callable either way, but the habit protects methods the gem does not
  know about.
- Override `cid` to derive identity elsewhere, `stream_name` for other
  streamables, `build_graph_actor` for a different error sink
  (`GraphActor.new(name:, on_error:)`), and read `graph_actor` to post work
  back onto the graph thread from a cable-thread callback.

`Hibiki::Rails::Debounce.new(actor:, wait:)` is an Effect `scheduler:`: at most
one run per `wait` window, trailing edge, posted back to the actor.
`Hibiki.batch` already coalesces writes within one action; Debounce is for the
cross-action burst (`broadcast_refresh_effect` uses it).

Full docs: https://planetaska.github.io/hibiki/channel-lifecycle/
