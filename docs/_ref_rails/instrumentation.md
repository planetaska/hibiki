---
title: Instrumentation
nav_order: 15
---

# Instrumentation

This page lists the events a hibiki_rails channel publishes, and shows how
to time actions and renders with them. Read it when you want to know how
long an action takes, which render is slow, or how long a visitor waited.
The events arrived in 0.18.0.

Rails already times a channel action, in `perform_action.action_cable`.
In a hibiki channel that event covers very little. The channel hands
each action to the *graph thread*, the one worker thread that owns a
subscription's signals and effects
([Channel lifecycle]({{ "/channel-lifecycle/" | relative_url }})
explains it), and Rails stops its clock when the hand-off returns. The
action, the effects it re-runs, and the renders those effects send all
happen afterward. The events below are published from the graph thread,
around the work itself.

## The events

All five go through `ActiveSupport::Notifications`, the same mechanism
Rails uses for its own events. They are always on and need no
configuration, and the gem subscribes to none of them.

| Event | Its duration covers | Payload |
| ----- | ------------------- | ------- |
| `subscribe.hibiki_rails` | `build_graph` and the first renders it sends | `channel` |
| `unsubscribe.hibiki_rails` | disposing the graph | `channel` |
| `action.hibiki_rails` | the action and every effect it re-ran | `channel`, `action`, `wait`, `renders` |
| `render.hibiki_rails` | one `broadcast_replace`, `broadcast_morph`, or `broadcast_refresh`: rendering the HTML and handing it to Action Cable | `channel`, `target`, `method` |
| `trip.hibiki_rails` | nothing; see [Trips](#trips-how-long-a-visitor-waited) | `channel`, `action`, `ack`, `paint` |

The payload keys:

- `channel` is the channel's class name, and `action` the name of the
  action method.
- `wait` is the time the action spent queued for the graph thread, in
  milliseconds. It grows when earlier actions on the same subscription
  are slow.
- `renders` is the number of broadcast renders the action caused.
- `target` is the DOM id the render replaces. `method` is `:replace`,
  `:morph`, or `:refresh`, and a refresh has no `target`.

## Subscribing

Subscribe in an initializer, as you would to any Rails event:

```ruby
# config/initializers/hibiki_metrics.rb
ActiveSupport::Notifications.subscribe("action.hibiki_rails") do |event|
  payload = event.payload
  Rails.logger.info(
    "#{payload[:channel]}##{payload[:action]} " \
    "#{event.duration.round(1)}ms, waited #{payload[:wait].round(1)}ms, " \
    "#{payload[:renders]} renders"
  )
end
```

**A subscriber runs on the graph thread.** While it runs, that visitor's
next action waits. Keep a subscriber to cheap work in memory, such as
adding to a counter, and do the slow part (a database write, a call to a
metrics service) elsewhere, on a timer or in a job.

With no subscriber, an event costs an action one to two microseconds.

## What is and is not published

- **An action the channel does not have publishes nothing.** The action
  name comes from the browser, so a subscriber that stores names is only
  ever given the names of your own action methods.
- **A raising action still publishes.** Its payload carries the
  exception under `:exception` and `:exception_object`, as any Rails
  event does.
- **A render with no action has no `action` event.** A model's
  `after_commit` ping or a debounced refresh re-runs an effect outside
  any action. Its `render` event is published as usual.
- **`transmit_value` and `transmit_url` have no event of their own.**
  Action Cable's `transmit.action_cable` covers them.
- **No event carries a byte count.** Action Cable's
  `broadcast.action_cable` fires inside the `render` event, on the same
  thread, and its payload holds the message. A subscriber that wants the
  size of each render can read it there.

## Counting subscriptions

`Hibiki::Rails.registry` knows the live subscriptions in the process:

```ruby
Hibiki::Rails.registry.size   # => 12
Hibiki::Rails.registry.tally  # => { "SongsChannel" => 9, "CounterChannel" => 3 }
```

Read these for a count. Adding up `subscribe` and `unsubscribe` events
drifts in development, where a code reload can drop a socket without the
`unsubscribe` running.

## Trips: how long a visitor waited

The server cannot time what a visitor felt. The acknowledgement that
ends an action and the HTML it rendered travel separately, and only the
browser sees both arrive. The JS client can time each round trip, a
*trip*, and report it:

```js
// app/javascript/application.js
import { HibikiController } from "hibiki-rails"

HibikiController.reportTrips = true
```

Reporting is off until you set this. Set it once, on the class, and
every island on the page reports.

An island then sends its recent trips along with its next action, and
the channel publishes one `trip.hibiki_rails` event for each:

- `ack` is the milliseconds from the action being sent to the server's
  acknowledgement arriving.
- `paint` is the milliseconds from the action being sent to its first
  render arriving, or `nil` when the action rendered nothing. An island
  that only uses `broadcast_refresh` always reports `nil`, because a
  refresh fetches the page instead of carrying HTML.

A `trip` event has no duration of its own; the two figures are its
content.

What reporting leaves out:

- The last trip on a page is never sent, since no action follows it.
- A trip the server dropped, or one that stalled, is not reported.
- An island sends at most its last five trips with one action.

**Treat trip figures as reported, not measured.** They come from the
visitor's browser, and anyone can send false ones. The channel accepts
at most five per action, only for its own action names, and clamps each
figure to between 0 and 60 000 ms. It cannot check them beyond that.

Trips ride on a third reserved payload key, `hbt`. Like `hbk`, the
channel removes it before your action method runs
([Driving an island]({{ "/driving-an-island/" | relative_url }})
describes the payload).
