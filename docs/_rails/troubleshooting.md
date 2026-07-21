---
title: Troubleshooting
nav_order: 11
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

Watch the Rails server log while you click (most cable lines are debug-level, which development's default log level shows):

- The subscription logs as `CounterChannel is transmitting the subscription confirmation` (or a rejection).
- Each action logs its signature, e.g. `CounterChannel#increment({...})`.
- Turbo broadcasts log as `[ActionCable] Broadcasting to ...` — check the stream name in that line matches what the page subscribed to with `turbo_stream_from`. The channel broadcasts to `[channel_name, cid]` by default; a mismatched or overridden `stream_name` fails silently, because broadcasting to a stream nobody listens on is not an error.
- Errors from actions and effects are reported to `Rails.error` with source `"hibiki_rails"` (see [Error handling layers]({{ "/error-handling-layers/" | relative_url }})) — an effect that raises on its first run simply never broadcasts, which looks identical to "nothing happens".

## The button doesn't work

If frames flow but a specific control does nothing, check the wiring between the DOM and the channel:

- The action name in the view must match a **public** method on the channel — `on(:increment)` / `data-action="counter#increment"` performs `increment`. Private methods are not client-invocable (by design).
- For the island/Phlex shapes, the control must sit **inside** the island element (the one stamped by `hibiki_island`), and the packaged controller must be registered — re-run `bin/rails g hibiki:rails:install`, or check that `app/javascript/controllers/hibiki_controller.js` exists and is loaded. A browser-console error like *"Failed to resolve module specifier"* or an unregistered-controller warning points here.
- For the Stimulus shape in a jsbundling/vite app, the controller must be registered in `controllers/index.js` (the generator appends it; `stimulus:manifest:update` also regenerates it).
- Check the browser **Console** tab for JS errors — a controller that throws in `connect()` never subscribes, and everything downstream stays dead.

## Updates arrive but the page doesn't change

- On the broadcast/transmit fragment transports, fragments are matched by **DOM id**: the `target:` in `broadcast_replace` (or the root id of a transmitted fragment) must equal the id of an element actually on the page. Typos here fail silently.
- For [reactive values]({{ "/reactive-values/" | relative_url }}), the `transmit_value` name must match the `reactive` placeholder name exactly, and a `ChannelController` subclass that overrides `received` must call `super`.

## The first update is lost

On the Turbo-broadcast transport, effects do their first run before the page's `turbo_stream_from` subscription confirms — subscribe the channel only after `streamConnected` resolves. See [the initial-state pattern]({{ "/rails-usage/" | relative_url }}). The generated shapes already handle this; hand-rolled controllers often miss it. The transmit transport doesn't have this problem.

## Signals change but effects don't re-run

Two core-library rules surface often in channels:

- Writing an **equal** value (`==`) is a deliberate no-op — it does not notify subscribers.
- Mutating a value in place (`items << item`, `hash[:k] = v`) doesn't write the signal at all, so nothing is notified. Assign a new value instead: `self.items = items + [item]`. See [the mutable-defaults reference]({{ "/mutable-defaults/" | relative_url }}).

## State resets in development

Editing a Ruby file disposes every live graph before code reloads; clients auto-reconnect and rebuild, so counters jump back to their initial values. That's expected — graph state lives in memory per connection, like any remount. See [Channel lifecycle]({{ "/channel-lifecycle/" | relative_url }}).
