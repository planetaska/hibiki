---
title: Troubleshooting
nav_order: 8
---

# Troubleshooting

A `hibiki_rails` page is a round trip. The browser holds one WebSocket
connection to the server, and everything travels over it: the click going
up, and the fresh HTML coming back down. When a page stops updating, the
trip broke somewhere along the way, and the fastest way to find where is
to follow it from one end to the other.

This page walks the trip in order. Each section names a symptom, says
where to look, and lists the usual causes. The last section covers
behaviors that look like bugs in development and are not.

## How an update travels

Knowing the stages makes the rest of the page easy to place. One click
goes through six of them:

1. **The browser sends the action.** The packaged JavaScript client, or a
   Stimulus controller of your own, sends a message over the WebSocket
   naming the action and carrying the control's value.
2. **The channel runs the action.** The message reaches a public method on
   your channel, which runs on that page's own thread.
3. **The action writes state.** A *state* is a value the channel keeps
   watch over. The action assigns it a new value, and the state notes
   which effects read it.
4. **Effects re-run.** An *effect* is a block that runs once, remembers
   every state it read, and runs again whenever one of them changes. In a
   channel, an effect usually renders HTML or computes a piece of text.
5. **The server sends the result.** The effect hands its HTML to a Turbo
   broadcast or to `transmit`, which sends it down the socket.
6. **The browser applies it.** The client finds the element whose DOM id
   matches the fragment and replaces it, or writes the text into every
   placeholder with that name.

[Rails usage]({{ "/rails-usage/" | relative_url }}) builds a page through
these stages one at a time. Stages 3 and 4 are the reactive core, and
[Introduction]({{ "/introduction/" | relative_url }}) explains them on
their own, without Rails.

## Start with the WebSocket

Everything rides one connection, so confirm it exists before reading any
code. Open the browser dev tools, go to the **Network** tab, and filter
by **WS**. A healthy page shows one `/cable` connection with status
`101 Switching Protocols`. Click it and open the **Messages** panel
(**Frames** in some browsers). Every subscription, action, and update
passes through this panel, which makes it the single most useful view
for the whole trip.

Three things should appear there:

- **On page load, a `subscribe` message and a `confirm_subscription`
  reply.** No reply means the server rejected the subscription. The
  common cause is a missing `cid` param, the per-page id the channel
  needs before it builds anything. A `reject` of your own, in a params
  check inside `subscribed`, has the same effect.
- **On a click, an outgoing `message` frame** carrying the action name.
- **After the click, an incoming frame with the update.** On the
  broadcast route it holds a `<turbo-stream>` element. On the transmit
  route it holds a small JSON object with an `html` or `value` key.

No `/cable` connection at all means Action Cable itself is not set up.
Check `config/cable.yml`, and check that the `ApplicationCable` files the
install generator writes are present.

## Then the server log

If the socket is up but nothing comes back, watch the Rails server log
while you click. Most cable lines log at debug level, which the
development default includes.

- **The subscription** logs as `CounterChannel is transmitting the
  subscription confirmation`, or as a rejection.
- **Each action** logs its call, such as `CounterChannel#increment({...})`.
  An action that never logs never reached the server, so the problem is
  on the browser side. See [The button does nothing](#the-button-does-nothing).
- **Each Turbo broadcast** logs as `[ActionCable] Broadcasting to ...`.
  The stream name in that line must match what the page subscribed to
  with `turbo_stream_from`. The channel broadcasts to the pair
  `[channel_name, cid]` by default. Broadcasting to a stream nobody
  listens on is not an error, so a mistyped or overridden `stream_name`
  fails silently.
- **Errors** from actions and effects go to `Rails.error` with the
  source `"hibiki_rails"`, and in development they also print to this
  log. An effect that raises on its first run never sends anything, which
  looks the same as "nothing happens" until you find the line.
  [Error handling layers]({{ "/error-handling-layers/" | relative_url }})
  explains where each kind of error lands.

## The button does nothing

Frames flow, other controls work, but one control does nothing. The
break is between the DOM and the channel.

- **The action name must match a public method on the channel.**
  `on(:increment)`, or `data-action="counter#increment"` in the Stimulus
  shape, calls a method named `increment`. Private methods cannot be
  called from the browser. That is a safety rule, not an oversight.
- **In the island and Phlex shapes, the control must sit inside the
  island element**, the one carrying the `hibiki_island` attributes. A
  control outside it belongs to no channel.
- **The packaged controller must be registered.** Check that
  `app/javascript/controllers/hibiki_controller.js` exists and loads, or
  run `bin/rails g hibiki:rails:install` again. A console error such as
  *"Failed to resolve module specifier"*, or a warning about an
  unregistered controller, points here.
- **In the Stimulus shape with jsbundling or Vite,** the controller must
  appear in `controllers/index.js`. The generator appends it, and
  `stimulus:manifest:update` regenerates the file.
- **Read the browser Console tab.** A controller that throws in
  `connect()` never subscribes, and every control inside it stays dead.

## The update arrives but the page does not change

An incoming frame shows in the Messages panel, and the page stays as it
was. The client received the update and found nowhere to put it.

- **Fragments are matched by DOM id.** The `target:` of a
  `broadcast_replace`, or the id on the root element of a transmitted
  fragment, must equal the id of an element already on the page. A typo
  on either side fails silently, because replacing a missing element is
  not an error.
- **Reactive values are matched by name.** The name passed to
  `transmit_value` must equal the name of the `reactive` placeholder,
  exactly. See [Reactive values]({{ "/reactive-values/" | relative_url }}).
- **A `ChannelController` subclass that overrides `received` must call
  `super`.** The base method is what writes values and swaps fragments.
  Without the call, the subclass receives every message and applies none.

## The first update never arrives

The page loads, its placeholders never fill, and yet later clicks work.
This is an ordering problem on the Turbo-broadcast route. The view's
`turbo_stream_from` opens a subscription of its own, and a broadcast
reaches the page only after that stream confirms. The channel's effects
run for the first time right after the channel subscribes. If the channel
subscribes first, the first broadcast goes to a stream nobody is
listening on yet, and the HTML is lost.

The fix is to subscribe the channel only after the stream confirms. The
packaged controller and both generated shapes already do so. A
controller written from scratch has to wait itself, using the exported
`streamConnected` helper, as
[Placeholders and the first update]({{ "/rails-usage/#placeholders-and-the-first-update" | relative_url }})
shows. The transmit route has no such trap: the client listens from the
moment it subscribes.

## The action runs but nothing is sent

The action logs on the server, raises nothing, and no frame comes back.
Before treating this as a bug, check the action against three rules of
the reactive core. All three come from one principle: an effect re-runs
when a value it read *changed*, not when something *happened*.

**Writing an equal value is a no-op.** Assigning a state the value it
already holds, as judged by `==`, notifies nobody. An action that sets a
flag already set, or writes a row the current filter excludes, changes
nothing, and the page rightly receives nothing. A busy indicator does not
wait for the update. It clears on a separate acknowledgement that the
server sends after every action, whether or not the action changed
anything, as [Loading state]({{ "/loading-state/#how-the-busy-flag-clears" | relative_url }})
describes.

**Changing a value in place is not a write.** `items << item` and
`hash[:k] = v` alter the object inside the state, and the state never
learns of it. Assign a new object instead:

```ruby
self.items = items + [item]
```

[Mutable state defaults]({{ "/mutable-defaults/#in-place-mutation-also-bypasses-reactivity" | relative_url }})
has the full account.

**An Active Record object equals any other with the same id.** Reloading
a record and assigning it back to the state produces a value that is `==`
to the old one even when its attributes moved, so the write is dropped.
In development, `hibiki_rails` logs a warning that starts with
`[hibiki_rails] State write dropped by ==` whenever this happens.
[Working with ActiveRecord]({{ "/working-with-active-record/#an-opt-in-upgrade-comparing-records-by-attributes" | relative_url }})
shows how to compare records by their attributes instead.

The rule also reaches effects that read a derived value. An action can
write a state, cause a derived to re-query the database, and still send
nothing, because the re-queried list compares equal to the old one. That
is the same rule seen from further away. An effect that must run on every
write, rather than on every change, should read something that changes
every time, such as a version counter.
[When an effect re-runs]({{ "/lifecycle-in-detail/#when-an-effect-re-runs" | relative_url }})
walks through the decision step by step.

## Normal in development

Two behaviors surprise people in development, and neither is a fault.

**Counters reset when you edit a Ruby file.** Before Rails reloads code,
`hibiki_rails` closes every connection that holds a live channel. The
browser reconnects on its own, the channel builds a fresh graph, and every
state goes back to its initial value. Graph state lives in memory for the
life of a subscription, like the state of a mounted component, so this is
the expected outcome of a reload.
[Channel lifecycle]({{ "/channel-lifecycle/#when-code-reloads-in-development" | relative_url }})
explains the mechanism.

**A new directory under `app/` raises `NameError` until you restart.**
Rails computes its autoload paths from the directories under `app/` at
boot. A directory created after boot, such as the `app/forms/` a
generator adds, is not an autoload root, and the files inside it stay
unknown no matter how many times the reloader runs. Restart the server.
Adding a file to a directory Rails already knows needs no restart.
Initializers in `config/initializers/` follow the same rule: they run
once at boot, so a change to one also needs a restart.
