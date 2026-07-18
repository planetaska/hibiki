# hibiki_rails

Rails glue for [hibiki](https://github.com/planetaska/hibiki):
connection-scoped signal graphs over ActionCable, pushing re-rendered HTML
to the page — either through Turbo Streams, or over the channel's own
subscription to the gem's packaged client (see "The packaged client").

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
- dev reloading — an Engine hook disposes every live graph before code
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

## The packaged client

The gem vendors its own JavaScript, turbo-rails-style: the engine puts
`hibiki.js` on the app's asset path and merges the `"hibiki"` pin into the
import map, so importmap-rails apps have no install step beyond
registering the controller — `bin/rails g hibiki:rails:install` does it
(plus the `Helpers` include below, the `ApplicationCable` boilerplate,
and the `@rails/actioncable` pin — a stock app has neither until its
first `rails g channel`), or add the line yourself:

```js
// app/javascript/controllers/index.js
import HibikiController from "hibiki"
application.register("hibiki", HibikiController) // identifier must be "hibiki"
```

(jsbundling/vite apps: copy `app/assets/javascripts/hibiki.js` into your
`app/javascript` — it's one self-contained module depending only on
`@rails/actioncable` and `@hotwired/stimulus`. An npm package is planned
once the gem is extracted.)

The client is one generic Stimulus controller that drives any *island*: a
DOM subtree bound to one channel subscription. Islands are stamped with
the opt-in `Hibiki::Rails::Helpers` — include it where you want the bare
names (`ApplicationHelper` for ERB, individual Phlex components); the gem
never includes it for you:

```erb
<%= tag.div(**hibiki_island(TodosChannel, cid: @cid)) do %>
  <%= render TodoList.new %>  <%# placeholder; replaced by DOM id %>
  <%= tag.form(**on(:add, event: :submit)) do %>
    <input type="text" name="title">
    <button>add</button>
  <% end %>
<% end %>
```

- `hibiki_island(channel, cid:)` — the island root: one subscription,
  identified by the page's `cid`.
- `on(action, event:, with:)` — forward a DOM event (`:click` default,
  `:change`, `:submit`) as a channel action, with `with:` as its payload.
  A changed control also sends `{ name => value }`; a submitted form sends
  its FormData and is reset after performing.

Transport is the channel's own subscription in both directions: render
effects call `transmit({ html: })` and the client swaps each fragment in
by its root DOM id (`Hibiki::Phlex.render_effect` pairs naturally):

```ruby
def build_graph
  @list = TodoList.new
  Hibiki::Phlex.render_effect(@list) { |html| transmit({ html: }) }
end
```

Because the client registers its `received` callback at subscribe time —
before the server ever runs `build_graph` — the effects' first transmits
always land: no Turbo stream, no connected-wait, and the server-rendered
initial HTML is only a paint-avoidance placeholder. One rule carries over
from any replace-fragment design: never transmit a fragment containing
the input the user is currently typing in.

The `data-hibiki-*` attributes the helpers emit are a private contract
with the vendored JS — they version together; don't hand-write them in
app code. The protocol itself is Stimulus-free (Stimulus only hosts the
controller lifecycle), so a hand-rolled client can drive the same
attributes: `toy-phlex/` in the parent repo does it in ~40 lines. The
helper interface's shape is inspired by
[phlex-reactive](https://phlex-reactive.zoolutions.llc)'s `on(...)`
actions.

## Generators

Each supported shape has a generator that scaffolds it as a *working*
mini-example — one state, one derived, one action, one effect; run it,
render the output from any page, click `+1`, watch it live-update — meant
to be reshaped in place, not filled in from scratch:

```sh
bin/rails g hibiki:rails:install                  # one-time wiring: register line,
                                                  # Helpers include, ApplicationCable
                                                  # boilerplate + actioncable pin
                                                  # (idempotent)
bin/rails g hibiki:rails:stimulus NAME [VIEW_PATH]  # channel + ChannelController
                                                    # subclass + view partial
bin/rails g hibiki:rails:island NAME [VIEW_PATH]    # channel + helpers-stamped view
                                                    # partial, no per-component JS
bin/rails g hibiki:rails:phlex NAME                 # channel + Phlex component +
                                                    # island wrapper (needs hibiki_phlex)
```

`VIEW_PATH` is the views directory under `app/views` (defaults to `NAME`);
the emitted partial is self-contained (`cid` defaults to a per-render
uuid), so `<%= render "counter/counter" %>` — or `<%= render
CounterIsland.new %>` for the Phlex shape — is the only line a page needs.
The `stimulus` shape works with zero wiring; `island` and `phlex` need the
one-time `hibiki:rails:install` (they print a hint when it's missing).
Namespaced names work (`admin/counter` pins `static channel` where the
Stimulus identifier can't infer it).

## The initial-state pattern (Turbo transport)

Islands on the Turbo-broadcast transport instead (the "Usage" example
above) have an ordering problem the transmit transport doesn't: the
graph's effects do their first run inside `subscribed` — usually before
the page's `turbo_stream_from` subscription has confirmed — so the first
broadcast would be lost. Fix the ordering on the client with the packaged
`streamConnected` helper: wait for Turbo to stamp the `connected`
attribute on the stream source, then subscribe the graph channel.

```js
// in the Stimulus controller driving the channel
import { streamConnected } from "hibiki"

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
