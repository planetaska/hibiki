# hibiki_rails

Rails glue for [hibiki](https://github.com/planetaska/hibiki):
connection-scoped signal graphs over ActionCable, pushing re-rendered HTML
to the page through Turbo Streams.

```
cable action arrives → mutate signals → effects render partials →
Turbo Streams broadcast → Turbo morphs the DOM
```

A graph lives per cable connection (in practice: per browser tab), built
when the channel subscribes and disposed when it unsubscribes. Effects
subscribe to whatever signals they read; when an action writes a signal,
exactly the affected effects re-render and broadcast.

Incubating inside the hibiki repo while the core gem is pre-release; will
be extracted to its own repository once hibiki 0.1.0 ships and this API
stabilizes. Rails >= 8.0 (what's tested), Ruby >= 3.4.

## Usage

```ruby
class CounterChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  # Runs once on the graph's own thread, inside Hibiki.root.
  def build_graph
    @count = Hibiki::State.new(0)
    @step  = Hibiki::State.new(1)
    doubled = Hibiki::Derived.new { @count.value * 2 }

    Hibiki::Effect.new do
      broadcast_replace target: "count", partial: "counter/count",
                        locals: { count: @count.value, doubled: doubled.value }
    end
    Hibiki::Effect.new do
      broadcast_replace target: "step", partial: "counter/step",
                        locals: { step: @step.value }
    end
  end

  # Actions are plain methods that touch signals directly: each one runs
  # on the graph thread inside one Hibiki.batch, so N writes still mean
  # one re-run per affected effect.
  def increment = @count.value += @step.value
  def burst     = 10.times { @count.value += 1 }
end
```

The page supplies a per-page-load graph id (`cid`) and listens on the
matching stream:

```erb
<div data-controller="counter" data-counter-cid-value="<%= @cid %>">
  <%= turbo_stream_from "counter", @cid %>
  <%= render "count", count: 0, doubled: 0 %>  <%# placeholder, see below %>
  ...
</div>
```

with `@cid = SecureRandom.uuid` in the controller action. The channel
broadcasts to `[channel_name, cid]` — override `stream_name` (and/or
`cid`) to derive identity differently.

## What the concern does

- `subscribed` — rejects without a `cid` param, then runs `build_graph`
  inside `Hibiki.root` on a dedicated worker thread (a `GraphActor`).
  ActionCable dispatches on a thread pool with no per-channel ordering;
  hibiki's threading model is confinement — so cable threads only enqueue,
  and the graph lives on exactly one thread.
- every action — the whole body is posted to that thread wrapped in one
  `Hibiki.batch`. `rescue_from` still applies (it runs on the graph
  thread); what it doesn't handle goes to `Rails.error` (source
  `"hibiki_rails"`).
- `unsubscribed` — disposes the root (running `on_cleanup` hooks) and
  stops the worker, draining what was already queued.
- dev reloading — a Railtie hook disposes every live graph before code
  reloads (stale effects would run old class versions forever); cable
  clients auto-reconnect and rebuild. Graph state resets on reload, like
  any remount.

## Broadcast helpers

Available inside effects (all bound to `stream_name`):

- `broadcast_replace(target:, **rendering)` — `partial:`/`locals:`,
  `html:`, or anything Turbo's renderer accepts.
- `broadcast_morph(target:, **rendering)` — replace via Turbo 8 morphing
  (keeps focus/scroll).
- `broadcast_refresh` — tell the page to refresh itself.
- `broadcast_refresh_effect(wait: 0.25) { ...read signals... }` — the
  morph-everything style: tracks whatever the block reads and answers
  changes with a debounced refresh, one per burst of actions rather than
  one per action.

## The initial-state pattern

The graph's effects do their first run inside `subscribed` — usually
before the page's `turbo_stream_from` subscription has confirmed, so that
first broadcast would be lost. Fix the ordering on the client: wait for
Turbo to stamp the `connected` attribute on the stream source, then
subscribe the graph channel.

```js
// wait for <turbo-cable-stream-source> to confirm before subscribing
export function streamConnected(element) {
  if (element.hasAttribute("connected")) return Promise.resolve()
  return new Promise((resolve) => {
    const observer = new MutationObserver(() => {
      if (element.hasAttribute("connected")) {
        observer.disconnect()
        resolve()
      }
    })
    observer.observe(element, { attributeFilter: ["connected"] })
  })
}
```

```js
// in the Stimulus controller driving the channel
async connect() {
  this.consumer = createConsumer()
  await streamConnected(this.element.querySelector("turbo-cable-stream-source"))
  this.subscription = this.consumer.subscriptions.create(
    { channel: "CounterChannel", cid: this.cidValue }, {}
  )
}
```

With that in place the server-rendered initial HTML is only a
paint-avoidance placeholder — the first broadcast always lands and
replaces it, so it doesn't have to match the graph's initial state.

## Error handling layers

1. `rescue_from` on the channel — handles action errors, on the graph
   thread.
2. `Hibiki.error_handler = ->(error, effect) { ... }` — app-level routing
   for effect errors raised during a flush (the gem does not set this).
3. The graph worker's per-job rescue — everything unhandled lands in
   `Rails.error.report(..., source: "hibiki_rails")`. Override per channel
   via `build_graph_actor` and `GraphActor.new(on_error:)`.

## Development

```
bundle exec rake   # specs + rubocop (same as CI)
```

The spec suite boots a minimal inline Rails app (`spec/support/dummy_app.rb`);
the live end-to-end proof app is `spike/` in the parent repo.
