---
title: Troubleshooting
nav_order: 8
---

# Troubleshooting

Everything in `hibiki_rails` rides one WebSocket, so most problems reduce to three questions: is the socket connected, is the server sending, and is the client applying what arrives. Work through them in that order.

## Is the WebSocket connected?

Open the browser dev tools, go to the **Network** tab, and filter by **WS**. You should see a `/cable` connection with status `101 Switching Protocols`. Click it and open the **Messages** (or **Frames**) panel — this is the single most useful debugging view, since every subscription, action, and update travels through it:

- On page load you should see a `subscribe` message for your channel and a `confirm_subscription` reply. No confirmation usually means the subscription was **rejected** — the most common cause is a missing `cid` param (the concern rejects without one).
- Clicking a button should produce an outgoing `message` frame carrying the action name.
- An update should come back as an incoming frame — a `<turbo-stream>` payload on the broadcast transport, or a `{ html: ... }` / `{ value: ... }` payload on the transmit transport.

If there is no `/cable` connection at all, ActionCable itself isn't set up — check `config/cable.yml` and that the install generator's `ApplicationCable` files exist.

## Is the server sending?

Watch the Rails server log while you click (most cable lines are debug-level, which development's default log level includes):

- The subscription logs as `CounterChannel is transmitting the subscription confirmation` (or a rejection).
- Each action logs its signature, e.g. `CounterChannel#increment({...})`.
- Turbo broadcasts log as `[ActionCable] Broadcasting to ...` — check the stream name in that line matches what the page subscribed to with `turbo_stream_from`. The channel broadcasts to `[channel_name, cid]` by default; a mismatched or overridden `stream_name` fails silently, because broadcasting to a stream nobody listens on is not an error.
- Errors from actions and effects are reported to `Rails.error` with source `"hibiki_rails"` (see [Error handling layers]({{ "/error-handling-layers/" | relative_url }})) — an effect that raises on its first run simply never broadcasts, which looks identical to "nothing happens".

## The button doesn't work

If frames flow but a specific control does nothing, check the wiring between the DOM and the channel:

- The action name in the view must match a **public** method on the channel — `on(:increment)` / `data-action="counter#increment"` performs `increment`. Private methods are not client-invocable (by design).
- For the island/Phlex shapes, the control must sit **inside** the island element (the one that carries the `hibiki_island` attributes), and the packaged controller must be registered — re-run `bin/rails g hibiki:rails:install`, or check that `app/javascript/controllers/hibiki_controller.js` exists and is loaded. A browser-console error like *"Failed to resolve module specifier"* or an unregistered-controller warning points here.
- For the Stimulus shape in a jsbundling/vite app, the controller must be registered in `controllers/index.js` (the generator appends it; `stimulus:manifest:update` also regenerates it).
- Check the browser **Console** tab for JS errors — a controller that throws in `connect()` never subscribes, and everything downstream stays dead.

## A new class raises `NameError` in development

If a class you just added under `app/` is not found — typically after running a generator that created a whole directory, like `app/forms/` — **restart the server**. Rails computes its autoload paths from the `app/*` glob **at boot**, so a directory that did not exist when the server started is not an autoload root, and nothing inside it is autoloadable no matter how many times the code reloader runs.

Adding a file to a directory Rails already knows about is fine and needs no restart. It is the new *directory* that doesn't reload.

The same rule catches `config/initializers/`: initializers run once at boot and do not reload. Change one and the server has to come back up.

## Updates arrive but the page doesn't change

- On the broadcast/transmit fragment transports, fragments are matched by **DOM id**: the `target:` in `broadcast_replace` (or the root id of a transmitted fragment) must equal the id of an element actually on the page. Typos here fail silently.
- For [reactive values]({{ "/reactive-values/" | relative_url }}), the `transmit_value` name must match the `reactive` placeholder name exactly, and a `ChannelController` subclass that overrides `received` must call `super`.

## The first update is lost

On the Turbo-broadcast transport, effects do their first run before the page's `turbo_stream_from` subscription confirms — subscribe the channel only after `streamConnected` resolves. See [Placeholders and the first update]({{ "/rails-usage/" | relative_url }}#placeholders-and-the-first-update). The generated shapes already handle this; hand-rolled controllers often miss it. The transmit transport doesn't have this problem.

## Signals change but effects don't re-run

Three core-library rules surface often in channels:

- Writing an **equal** value (`==`) is a deliberate no-op — it does not notify subscribers.
- An effect re-runs only when a value it actually read has **changed** (`==`), compared at the batch flush. So an action can write signals, invalidate deriveds, re-query the database, and still correctly broadcast **nothing**. See [when an effect re-runs]({{ "/lifecycle-in-detail/" | relative_url }}).
- Mutating a value in place (`items << item`, `hash[:k] = v`) doesn't write the signal at all, so nothing is notified. Assign a new value instead: `self.items = items + [item]`. See [the mutable-defaults reference]({{ "/mutable-defaults/" | relative_url }}).

The second one is worth sitting with before treating a silent action as a bug. An action that toggles a row already in the state it was asked for, or that writes a row excluded by the current filter, costs **zero bytes on the wire** — that is the gate working, not a fault. It is also why the client clears its busy indicator on a [post-batch ack]({{ "/the-js-client/" | relative_url }}) rather than on an incoming render: waiting for bytes that never come would leave a spinner on forever.

The trap in the other direction: an effect that must fire on every *write* rather than every *change* should read a value that genuinely changes — a version counter, not a re-queried list that happens to compare equal.

## State resets in development

Editing a Ruby file disposes every live graph before code reloads; clients auto-reconnect and rebuild, so counters jump back to their initial values. That's expected — graph state lives in memory per connection, like any remount. See [Channel lifecycle]({{ "/channel-lifecycle/" | relative_url }}).
