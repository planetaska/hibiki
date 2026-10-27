# Instrumentation

Since 0.18.0 a channel publishes `ActiveSupport::Notifications` events from
the graph thread. Always on, nothing to configure; the gem subscribes to none.
Rails' own `perform_action.action_cable` covers only the hand-off to the graph
thread, not the action, its effects or its renders.

| Event | Duration covers | Payload |
| --- | --- | --- |
| `subscribe.hibiki_rails` | `build_graph` and its first renders | `channel` |
| `unsubscribe.hibiki_rails` | disposing the graph | `channel` |
| `action.hibiki_rails` | the action and every effect it re-ran | `channel`, `action`, `wait`, `renders` |
| `render.hibiki_rails` | one `broadcast_replace` / `broadcast_morph` / `broadcast_refresh` | `channel`, `target`, `method` |
| `trip.hibiki_rails` | nothing | `channel`, `action`, `ack`, `paint` |
| `skip.hibiki_rails` | nothing: a `replaceable` action the next one replaced before it ran (since 0.21.0) | `channel`, `action`, `wait` |

- `channel` is the class name, `action` the method name.
- `wait`: ms the action queued for the graph thread. `renders`: broadcast
  renders it caused. A skipped action publishes `skip`, never `action`.
- `method`: `:replace`, `:morph` or `:refresh`; a refresh has no `target`.

```ruby
# config/initializers/hibiki_metrics.rb
ActiveSupport::Notifications.subscribe("action.hibiki_rails") do |event|
  Rails.logger.info "#{event.payload[:channel]}##{event.payload[:action]} #{event.duration.round(1)}ms"
end
```

Rules:

- A subscriber runs on the graph thread and holds up that visitor's next
  action. Do cheap in-memory work there; write to a database or a metrics
  service elsewhere.
- An action the channel does not have publishes nothing, so a subscriber only
  sees real action names.
- A raising action still publishes, with `:exception` in the payload.
- A render outside any action (an `after_commit` ping, a debounced refresh)
  has a `render` event and no `action` event.
- `transmit_value` and `transmit_url` have no event; use Action Cable's
  `transmit.action_cable`.
- No byte counts. `broadcast.action_cable` fires inside the `render` event on
  the same thread and carries the message.
- Count subscriptions with `Hibiki::Rails.registry.size` and
  `registry.tally` (`{ "SongsChannel" => 9 }`), not by adding up events: a
  development reload can drop a socket without `unsubscribe`.

## Trips

The browser's timing of one action, off by default:

```js
// app/javascript/application.js
import { HibikiController } from "hibiki-rails"
HibikiController.reportTrips = true
```

Each island then sends its last trips (at most five) with its next action,
under the reserved payload key `hbt`, and the channel publishes one `trip`
event for each.

| Key | Meaning |
| --- | --- |
| `ack` | ms from sending the action to the server's ack arriving |
| `paint` | ms from sending the action to its first render arriving; `nil` when it rendered nothing, and always `nil` on a refresh-only island |

- Not reported: the last trip on a page, a dropped trip, a stalled trip.
- The figures come from the browser and can be forged. The channel takes at
  most five per action, only for its own action names, clamped to 0..60000 ms.
- `perform_action` removes `hbt`, like `hbk`, before the action method runs.

Full docs: https://planetaska.github.io/hibiki/instrumentation/
