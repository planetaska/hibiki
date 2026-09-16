---
name: hibiki-rails
description: >-
  Rails integration for hibiki (hibiki_rails 0.15.0 + npm hibiki-rails 0.15.0): channels with Hibiki::Rails::Channel, build_graph and public-method actions, transmit({ html: }), transmit_value, transmit_url, broadcast_replace/morph/refresh(_effect), the island/hibiki_island/on/reactive/reactive_attrs helpers, subscribe params, the JS client (HibikiController, ChannelController, perform/performOn, fallback:, debounce:, confirm:, visible), loading state (data-hibiki-busy, data-hibiki-state), channel lifecycle and the graph thread, error layers, ActiveRecord patterns (Hibiki::Rails.record_equals, db_version, after_commit pings), hibiki:rails:install, troubleshooting. Load for any app/channels/*_channel.rb using Hibiki, any view with island/on, "page doesn't update", "first update never arrives", "button does nothing", "State write dropped by ==". Load hibiki-rails-forms for ReactiveForm, hibiki-rails-scaffold for generators, hibiki-rails-motion for data-motion, hibiki-phlex for Phlex components.
license: MIT
metadata:
  author: planetaska
  hibiki: "0.3.0"
  hibiki_rails: "0.15.0"
  hibiki_phlex: "0.1.0"
---

# hibiki-rails

hibiki_rails 0.15.0 and npm hibiki-rails 0.15.0, in lockstep; the family versions table lives in the `hibiki` skill.

## The round trip

Keep the state of a page region on the server, in signals, and let effects
re-render its HTML when that state changes. Every click is one trip: the
browser sends an action over ActionCable, the action writes signals, the
effects that read them re-render their fragments, and the HTML comes back to
replace the old fragment by DOM id. An ActionCable channel owns the graph,
building it when a tab subscribes and disposing it when the tab leaves, so one
subscription is one graph and two tabs never share state. Requires Rails
>= 8.0 and Ruby >= 3.4; the gem depends on `hibiki` (~> 0.3) and `turbo-rails`.

## Install

Add `gem "hibiki"` and `gem "hibiki_rails"`, then run
`bin/rails g hibiki:rails:install`. Every step is idempotent. It writes
`app/javascript/controllers/hibiki_controller.js`, a one-line shim
(`export { default } from "hibiki-rails"`) registering the packaged controller
as `hibiki` (a real controller file, so `stimulus:manifest:update` re-derives
the registration instead of dropping it); on jsbundling/vite (no
`config/importmap.rb`) the import/register pair in
`app/javascript/controllers/index.js`; `include Hibiki::Rails::Helpers` in
`app/helpers/application_helper.rb`, because the gem never mixes the helpers
into your views for you; and `app/channels/application_cable/channel.rb` plus
`connection.rb` when missing, since a stock app has none until its first
`rails g channel`.

Importmap apps are then done: the engine merges the pins `hibiki-rails` and
`hibiki-rails/motion` (opt-in motion) into the import map. Bundler apps run
`npm add hibiki-rails` pinned to the gem's version; peers are
`@hotwired/stimulus >= 3.2` and `@hotwired/turbo-rails >= 8.0`. No
`@rails/actioncable` pin since 0.11.0, because the client rides turbo-rails'
consumer. Phlex components include `Hibiki::Rails::Helpers` themselves.

## A channel by hand

```ruby
# app/channels/counter_channel.rb
class CounterChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @count = Hibiki::State.new(0)
    @step  = Hibiki::State.new(1)
    doubled = Hibiki::Derived.new { @count.value * 2 }

    Hibiki::Effect.new do
      broadcast_replace target: "count", partial: "counter/count",
                        locals: { count: @count.value, doubled: doubled.value }
    end
  end

  def increment = @count.value += @step.value
  def set_step(data) = @step.value = Integer(data["step"])
end
```

- Keep signals in instance variables so actions can reach them; `build_graph`
  runs once per subscription, inside `Hibiki.root`, on the graph thread.
- Let actions only write signals, never render: the effects re-render on
  their own. Each body runs on the graph thread inside one `Hibiki.batch`, so
  ten writes still mean one re-run per affected effect. A one-parameter action
  gets a string-keyed hash; `perform_action` strips the reserved `hbk` key.
- Every public method is a client-callable action, so keep the rest `private`;
  only `HIDDEN_ACTIONS` (`build_graph`, `subscribed`, `unsubscribed`) are hidden.

## Views: two shapes, one protocol

Both shapes emit the same `data-hibiki-*` attributes, a private Ruby-to-JS
contract you never write by hand. Island shape, ERB, no JavaScript of yours:

```erb
<%= island CounterChannel do %>
  <%= render "counter/count", count: 0, doubled: 0 %>
  <%= tag.button("+1", **on(:increment)) %>
  <%= tag.input(type: "number", name: "step", value: 1, **on(:set_step, event: :change)) %>
<% end %>
```

- `island(channel, cid:, params:, transport:, tag_name:, **attrs) { |cid| }`
  generates a UUID cid, stamps the root, and adds
  `turbo_stream_from channel.channel_name, cid` unless `transport: :transmit`.
  ERB-only (it needs `capture`, so it raises elsewhere), class-only, no strings.
- `hibiki_island(channel, cid:, params:)` is the primitive
  (`tag.div(**hibiki_island(CounterChannel, cid:))`), the form Phlex uses.
- `on(action, event: :click, with:, debounce:, confirm:, reset:, fallback:)`
  marks a control. `:input` defaults to a 250 ms debounce; `reset: false`
  keeps a submitted form's inputs; `fallback: true` makes its own href or
  action the degraded path. A changed control sends its value under its
  `name`, a form its FormData. Table: `references/the-js-client.md`.

Stimulus shape, with a controller of your own: the root carries
`data-controller="counter"`, `data-counter-cid-value`, and
`turbo_stream_from "counter", cid`; the controller
`extends ChannelController` (import from `"hibiki-rails"`), which infers
`CounterChannel` from the identifier (`static channel = "Admin::CounterChannel"`
when it cannot) and forwards plain `data-action="counter#increment"` tokens as
payload-less actions, so declare a method only when it needs a payload:
`setStep(event) { this.perform("set_step", { step: event.target.value }) }`.

## Two routes for the HTML

| Channel renders with | `turbo_stream_from` in the island | First-update trap |
| --- | --- | --- |
| `broadcast_replace`, `broadcast_morph`, `broadcast_refresh` | yes (`island` adds it by default) | yes: a broadcast lands only after the stream confirms; the packaged controller waits with `streamConnected`, a hand-written client must too |
| `transmit({ html: })`, `transmit_value`, `transmit_url` | no (`transport: :transmit`) | none: `received` is registered before `build_graph` runs |

Both routes swap by DOM id, so give every fragment root a stable, page-unique
id; a typo fails silently. One channel may use both. Never transmit the fragment
holding the input being typed in; morph where a form is open, since a replace drops the caret.

## Reactive values and the address bar

Send one piece of text instead of a fragment. A placeholder,
`<h1>todos (<%= reactive :remaining, 0 %> left)</h1>`, and a channel block in
`build_graph`, `transmit_value(:remaining) { @list.remaining }`, are joined by
a name that must be unique across the page. Values are text only (assigned as `textContent`), matched by name
document-wide like a class, so a nav badge and a heading can share one.
`transmit_value` and `transmit_url` are equality-gated on the emitted string,
so a run whose text matches the last one sends nothing. `transmit_url { ... }`
mirrors state into the address bar with `history.replaceState`; compute a
same-origin path and omit params at their defaults. See
`references/reactive-values.md`.

## Broadcast helpers

All private (a public helper would become an action), all bound to
`stream_name`, default `[channel_name, cid]`:

- `broadcast_replace(target:, **rendering)`: replace the element with DOM id
  `target`; `partial:`/`locals:`, `html:`, or anything Turbo's renderer takes.
- `broadcast_morph(target:, **rendering)`: the same as a Turbo 8 morph, which
  keeps focus and scroll but needs a stable id on every child of the container.
- `broadcast_refresh`: the page re-fetches and morphs itself;
  `broadcast_refresh_effect(wait: 0.25) { ...reads... }` wraps it in an effect
  on a `Hibiki::Rails::Debounce` scheduler, one refresh per burst of actions.

A channel renders outside any request (empty `params` and `session`, nil
`action_name`, no controller ivars, nothing raises), so pass everything through
`locals:` under a strict-locals header (`<%# locals: (books:) -%>`);
`assigns:` is the escape hatch. See `references/broadcast-helpers.md`.

## Channel lifecycle and threads

- Each subscription gets a `Hibiki::Rails::GraphActor`, one worker thread;
  cable threads only `post` closures to it, because the core is lock-free by
  confinement. Every job runs inside `Rails.application.executor`, so
  `ActiveSupport::CurrentAttributes` reset between actions; read
  `current_user` from the connection at the point of use instead.
- `subscribed` rejects without `cid`, then posts `Hibiki.root { build_graph }`;
  `unsubscribed` posts the dispose and closes the queue, so in-flight jobs
  drain first and a later action is acked `dropped: true`. Overrides call
  `super` and stay private. Before a dev reload the engine disposes every live
  graph, so counters reset on edit. See `references/channel-lifecycle.md`.

## Working with ActiveRecord

Two rules: records stop at the boundary (a plain copy, or a frozen record
behind a real comparator, is what crosses into a signal), and every database
write pairs with a signal write, since the database cannot announce its own
changes. The snippets below use the `Hibiki::Reactive` macros, so they belong
in a reactive object the channel holds (`@list = TodoList.new` in
`build_graph`, actions delegating to it); `build_graph` itself has no `state`
or `derived` macro, so spell the same thing there with `Hibiki::State.new` and
`Hibiki::Derived.new` in ivars, as in the channel above. Patterns, ranked:

1. Version signal + lazy derived query, the default for lists:

```ruby
class TodoList
  include Hibiki::Reactive

  state :db_version, 0
  derived(:items) do
    db_version   # the tracked dependency; the query re-runs when it bumps
    Todo.order(:id).map { Row.new(id: it.id, title: it.title, done: it.done) }
  end
  def invalidate = self.db_version += 1
  def toggle(id) = (Todo.find(id).toggle!(:done); invalidate)
end
```

Inside `build_graph` the same pattern is `@db_version = Hibiki::State.new(0)`
and `@items = Hibiki::Derived.new { @db_version.value; Todo.order(:id).map { ... } }`,
with `@db_version.value += 1` in the action.

2. `state(:items, equals: Hibiki::Rails.record_equals) { fetch }` over
   `Todo.order(:id).strict_loading.map { it.readonly!; it.freeze }`: compares
   class + `attributes` (recursing through arrays) so a reloaded record no
   longer equals its stale self, and freezing turns mutation into an exception.
3. Snapshot + write-through: `Data` rows in state, `self.items = fetch` after
   every mutator; forget one and the page goes stale silently.
4. Editing one record: a reactive form, so load `hibiki-rails-forms`.

Other writers (controllers, jobs, other tabs) reach the graph through a model
ping, `after_commit { ActionCable.server.broadcast("todos:changed", {}) }`,
which the channel subscribes to in a private `subscribed` (after `super` and a
`subscription_rejected?` check) with `stream_from "todos:changed" do ... end`;
the block runs on a cable thread, so it hops first with
`graph_actor&.post { Hibiki.batch { @list.invalidate } }`.

Gotchas: bulk writes (`update_all`, `insert_all`, `update_columns`, raw SQL)
skip the callback, so ping by hand; the `async` cable adapter is in-process,
so a separate worker needs `solid_cable` or `redis`; 500 saves mean 500 pings,
so quiet the callback with a thread-local and ping once; scope stream names
from the connection's identity, never from a client param. See
`references/working-with-active-record.md`.

## Loading and connection state

The client writes read-only attributes for your CSS (start with
`[data-hibiki-busy] { opacity: 0.6 }`): `data-hibiki-busy` and
`aria-busy="true"` on the island root while an action is in flight,
`data-hibiki-busy` on the firing control, and `data-hibiki-state` on the root
(`connecting`, `ready`, `offline`, `stalled`). Busy clears on the server's
`hbk` ack, not on returning HTML, because an equal write may send zero bytes.
Clicks queue only during the first connect window; after a drop they are
dropped, since a reconnect builds a fresh graph. Timings are statics on the
controller class (`busyDelay` 150, `busyGrace` 60, `busyCeiling` 10000 ms),
changed by subclassing `HibikiController` in the shim. See
`references/loading-state.md`.

## Driving an island from JS

`import { performOn } from "hibiki-rails"`, then
`performOn(element, "nested_move", { path, to })` finds the island containing
the element and calls its public `perform(action, payload)`. A truthy return
(the seq) means accepted, so leave the DOM as the user arranged it;
`undefined` means dropped (offline, dead socket, or no island, with a console
warning), so revert the gesture yourself. See `references/driving-an-island.md`.

## Error handling layers

1. `rescue_from` catches action-body errors on the graph thread; it never sees
   effect errors, which run after the body returns.
2. `Hibiki.error_handler = ->(error, effect) { ... }` in an initializer (the
   core gem's hook) receives errors from effect re-runs; hibiki_rails leaves it
   unset, so set it yourself. A first-run error inside `build_graph` is not a
   re-run, so it skips this layer and the fragment never renders.
3. The GraphActor safety net catches the rest per job, keeps the thread alive,
   still acks, and calls `Rails.error.report(error, handled: true, source:
   "hibiki_rails")`, logging `[hibiki_rails] <Class>: <message>` in development
   and test. Replace it per channel with
   `def build_graph_actor = Hibiki::Rails::GraphActor.new(on_error: ->(e) { ... })`.
   See `references/error-handling-layers.md`.

## Troubleshooting order

Follow the trip end to end, because each symptom sits on one stage of it:

1. Network tab, filter WS: one `/cable` at `101`, then its Messages panel.
   Expect `subscribe` then `confirm_subscription` (none: a missing `cid` or
   your own `reject`), an outgoing `message` frame per click (none: no public
   method of that name, a control outside the island, an unregistered shim, or
   a controller that threw in `connect()`), then an incoming `<turbo-stream>`
   or JSON frame with `html`, `value`, or `url`.
2. Server log: `CounterChannel#increment({...})`, `[ActionCable] Broadcasting
   to ...` (must match the page's `turbo_stream_from`), `[hibiki_rails]` lines.
3. Frame arrived, page unchanged: a DOM id or value name mismatch, or a
   `received` override without `super`.

When the action logs and nothing is sent, apply the three graph rules: equal
writes are no-ops; in-place mutation is not a write (`self.items = items +
[item]`); AR `==` is class + id, so a reloaded record is dropped (dev log:
`[hibiki_rails] State write dropped by == ...`). See `references/troubleshooting.md`.

## Pitfalls

- Broadcast helpers need `turbo_stream_from` in the island; transmit does not. Each route has its own listener, and `island` writes the line unless `transport: :transmit`. (rails-usage)
- The first broadcast is lost when the channel subscribes before the stream confirms. Wait on `streamConnected` in a hand-written client; the packaged one already does. (rails-usage)
- A wrong `target:` id or value name fails silently. Replacing a missing element is not an error. (troubleshooting)
- An equal write sends zero bytes, yet busy clears. The `hbk` ack, not the HTML, ends a trip. (loading-state)
- Every public channel method is an action. Only `build_graph`, `subscribed`, `unsubscribed` are hidden; make the rest private. (rails-usage)
- A subscription without `cid` is rejected. The per-page id is what gives each tab its own graph. (channel-lifecycle)
- Only the graph thread may touch signals. A `stream_from` callback runs on a cable thread, so hop with `graph_actor&.post { Hibiki.batch { ... } }`. (working-with-active-record)
- `Current.*` resets between actions. Each job runs in the executor; read `current_user` from the connection instead. (channel-lifecycle)
- Channel renders have no request. `params`, `session`, controller ivars are absent and nothing raises; use strict locals. (broadcast-helpers)
- AR `==` swallows a reloaded record, and mutating a live record in a signal is not a write. Development logs `[hibiki_rails] State write dropped by == although attributes differ`; use `equals: Hibiki::Rails.record_equals` on frozen rows, or plain copies. (working-with-active-record)
- A derived that reads no signal computes once forever. `derived(:remaining) { Todo.where(done: false).count }` never re-queries; read `db_version` first. (working-with-active-record)
- Bulk writes skip `after_commit`, the `async` adapter stays in-process, each save pings once, a global stream wakes everyone. Ping by hand, use solid_cable/redis across processes, batch pings, scope the stream. (working-with-active-record)
- Subscribe params are untrusted. Look up inside a scope you choose and `reject` on a miss; never interpolate one into a stream or class name. (the-js-client)
- `island` is ERB-only. Phlex components use `div(**hibiki_island(...))`. (the-js-client)
- `:input` debounces 250 ms by default. Pass `debounce: 0` for every keystroke. (the-js-client)
- The default form reset is wrong for edit forms. It runs before the reply, so a failed commit discards the input; pass `reset: false`. (the-js-client)
- `data-turbo-confirm` is ignored on a hibiki control. Use `confirm:`, which also gates the fallback path. (the-js-client)
- A `visible` control never gets `fallback:`. Off-ready, scrolling into view would navigate; split it into a sentinel wrapper and an inner fallback link. (the-js-client)
- Morph needs a stable id on every child of the container. An id-less trailing node is matched positionally and rebuilt. (broadcast-helpers)
- A `received` override must call `super`. The base method writes values and swaps fragments; acks still clear without it. (reactive-values)
- Importmap apps use the vendored pin; bundler apps install npm `hibiki-rails` at the gem's version. Mixing versions breaks the private attribute contract. (version-lockstep)
- A first-run effect error bypasses `Hibiki.error_handler`. It lands in the safety net and the fragment never renders; check the log. (error-handling-layers)
- A placeholder inside a replaced fragment must render its current value, and `transmit_url` is same-origin only. The swap resets the text and the gate will not re-send; another origin is refused silently. (reactive-values)
- Clicks during an offline gap are dropped, not queued. A reconnect builds a fresh graph the old intent was not formed against. (loading-state)
- Dev reload resets every graph, and a new `app/*` directory needs a restart. Autoload roots are computed at boot. (troubleshooting)

## Reference files

- `references/rails-quick-start.md`: install steps, what the generator writes, importmap vs bundler, first component.
- `references/rails-usage.md`: channel anatomy, the three view shapes, cid, the two routes, placeholders, rendering without a request.
- `references/the-js-client.md`: helper signatures, the `on` option table, payload shapes, `visible`, fallback contract, subscribe-param trust, message shapes, `hibiki:before-render`, exports.
- `references/reactive-values.md`: `reactive`/`reactive_attrs` + `transmit_value`, text-only rules, `transmit_url`.
- `references/broadcast-helpers.md`: the four signatures, morph vs replace, rendering outside a request, `stream_name`.
- `references/channel-lifecycle.md`: GraphActor, executor wrap, subscribe/unsubscribe, hooks, dev reload.
- `references/error-handling-layers.md`: `rescue_from`, `Hibiki.error_handler`, the safety net, `build_graph_actor`.
- `references/loading-state.md`: attribute table, four states, queue rules, the ack, timing statics.
- `references/driving-an-island.md`: `performOn`/`perform` contract, the SortableJS pattern, what the server receives.
- `references/working-with-active-record.md`: the two rules, ranked patterns, the `after_commit` bridge, controller/job gotchas.
- `references/troubleshooting.md`: symptom table, the three "nothing sent" rules, normal-in-development behaviors.
- `references/version-lockstep.md`: the gem/npm release table and the pin rule.

## Related skills

- `hibiki`: the core signals (State/Derived/Effect, batch, `equals:`, threading), the family router, the versions table.
- `hibiki-rails-forms`: `Hibiki::Rails::ReactiveForm`, nested forms, multi-select, file uploads.
- `hibiki-rails-scaffold`: `hibiki:rails:scaffold` and the other generators, `--phlex` included.
- `hibiki-rails-motion`: `data-motion`, the `hbk-*` utilities, `hibiki-rails/motion`.
- `hibiki-phlex`: reactive Phlex components with `Hibiki::Phlex.render_effect`.
