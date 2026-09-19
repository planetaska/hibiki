# Troubleshooting

A page is one round trip over one WebSocket: action up, HTML down. Follow the
trip from end to end. Six stages: the browser sends the action; the channel
runs it on the graph thread; the action writes state; effects re-run; the
server broadcasts or transmits; the browser applies by DOM id or value name.

| Symptom | Where to look | Usual causes |
| --- | --- | --- |
| Nothing works | Network tab, filter WS: one `/cable` at `101 Switching Protocols` | no connection at all: `config/cable.yml`, missing `ApplicationCable` files (re-run `hibiki:rails:install`) |
| No `confirm_subscription` after `subscribe` in the Messages panel | same panel | subscription rejected: missing `cid`, or your own `reject` in `subscribed` |
| Button does nothing (no outgoing `message` frame) | Messages panel, then the Console | action name matches no public method (private ones are unreachable by design); control outside the island element; shim `hibiki_controller.js` missing or not registered (`Failed to resolve module specifier`, or not in `controllers/index.js` on jsbundling); a controller threw in `connect()` |
| Action never logs | server log (`CounterChannel#increment({...})` at debug) | the frame never reached the server: see the row above |
| Broadcast logged, page unchanged | `[ActionCable] Broadcasting to ...` | stream name differs from the page's `turbo_stream_from`; default is `[channel_name, cid]`; broadcasting to no listener is not an error |
| Update frame arrives, page unchanged | Messages panel shows `<turbo-stream>` or `{ html }` / `{ value }` | `target:`/fragment root id matches no element; `transmit_value` name differs from the `reactive` name; a `received` override without `super` |
| First update never arrives, later clicks work | broadcast route only | channel subscribed before the stream confirmed; wait on `streamConnected` in a hand-written client (packaged shapes already do); transmit has no such trap |
| Fragment stopped updating, nothing in the log | server log for `[hibiki_rails]` lines | an effect raised (first-run errors never send); errors go to `Rails.error` with source `"hibiki_rails"` and print in development |
| Action logs, raises nothing, no frame | the three rules below | the action changed nothing the graph can see |

The three "nothing sent" rules, all one principle (an effect re-runs when a
value it read changed, not when something happened):

1. Writing an equal value is a no-op. A flag already set, a filter already at
   that value: nothing notifies, and busy still clears on the ack.
2. Changing a value in place is not a write. `items << item` and
   `hash[:k] = v` alter the object inside the state; assign a new one:
   `self.items = items + [item]`.
3. An AR record equals any other with the same id. A reloaded record assigned
   back is dropped; development logs
   `[hibiki_rails] State write dropped by == although attributes differ`.
   Compare by attributes (`equals: Hibiki::Rails.record_equals`) or copy.

The rules reach through deriveds: an action can bump a state, cause a derived
to re-query, and still send nothing because the new list `==` the old. An
effect that must run on every write should read something that changes every
time, such as a version counter.

All three look like a trip that worked. The action logs, the server sends the
`{ ack: seq }` reply whatever the action did, and busy clears on that ack; only the HTML
is missing, because zero bytes were sent. Name this when you diagnose one: a
spinner that clears proves the action ran, not that a value changed.

Normal in development:

- Counters reset when you edit a Ruby file: hibiki_rails closes every live
  channel before a reload, clients reconnect, `build_graph` runs fresh.
- A new directory under `app/` raises `NameError` until you restart: autoload
  roots are computed at boot, so `app/forms/` added by a generator is unknown
  until then. Initializers likewise need a restart.

Full docs: https://planetaska.github.io/hibiki/troubleshooting/
