# Loading and connection state

The client records what it knows as attributes on the island; your CSS makes
them visible. It renders no UI of its own.

| Where | Attribute | Meaning |
| --- | --- | --- |
| island root | `data-hibiki-busy` | an action is in flight |
| island root | `aria-busy="true"` | the same, for assistive tech |
| island root | `data-hibiki-state` | `connecting`, `ready`, `offline`, or `stalled` |
| firing control | `data-hibiki-busy` | this control started the trip (a `submit` marks the form, not its button) |

These four are read-only, written at runtime; every other `data-hibiki-*`
attribute is emitted by a helper and private. `data-motion` and the
`data-motion-leaving` / `data-motion-entering` pair are the other public
family (see the `hibiki-rails-motion` skill).

```erb
<%= island TodosChannel do %>
  <span class="spinner" aria-hidden="true"></span>
  <span class="offline-note">Connection lost, reconnecting</span>
<% end %>
```

```css
.spinner, .offline-note                     { display: none }
[data-hibiki-busy] .spinner                 { display: inline-block }   /* descendant, not child */
[data-hibiki-state="offline"] .offline-note { display: inline }
[data-hibiki-state][data-hibiki-busy]       { opacity: 0.6 }            /* island busy */
[data-hibiki-busy]:not([data-hibiki-state]) { }                         /* control busy */
```

| State | When | On screen |
| --- | --- | --- |
| `connecting` | set synchronously at connect, before the subscription opens | real content, inert: clicks are queued |
| `ready` | subscription confirmed | normal |
| `offline` | socket dropped; ActionCable retries | content frozen; clicks dropped |
| `stalled` | an action outlived `busyCeiling` with no ack | "we lost it", said plainly |

There is no "loading" state: the page arrives server-rendered and full, and
every update replaces valid content with newer content, so during a trip the
content is stale, not absent. Dim it or badge it; do not swap in a skeleton.

Queueing: clicks during the first connect window are queued and flushed when
the subscription confirms, because `Subscription#perform` silently drops on
an unopened socket. After a later drop, clicks are dropped, not queued: a
reconnect builds a fresh graph with default state, and a replayed click could
mean something else to it.

How busy clears: every performed action carries a sequence number under the
reserved payload key `hbk`, stamped last so a form field of that name cannot
overwrite it (`action` is ActionCable's own reserved key). The server sends it
back as an ack after the batch, and the ack clears the flag. Returning HTML
cannot be the signal, because an equal write legitimately sends zero bytes.
The base class handles acks before `received`, so a subclass override without
`super` still clears.

| Static | Default | Meaning |
| --- | --- | --- |
| `busyDelay` | 150 ms | a trip shorter than this shows nothing, so fast trips do not flash |
| `busyGrace` | 60 ms | keep the flag up after the ack, so trailing HTML lands while still busy |
| `busyCeiling` | 10000 ms | give the trip up and mark the island `stalled` |

```js
// app/javascript/controllers/hibiki_controller.js
import { HibikiController } from "hibiki-rails"
class SlowLink extends HibikiController { static busyDelay = 400 }
export default SlowLink
```

There is no per-island option on purpose: the timings compensate for the
network and the server, which every island shares. Two habits to drop:
optimistic UI (the state is on the server, so the page cannot change before
it speaks) and request/response thinking (the ack promises only that the
action ran; content is owned by effects and may arrive later or never).

Full docs: https://planetaska.github.io/hibiki/loading-state/
