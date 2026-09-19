# The JS client

The gem vendors `hibiki.js` (npm `hibiki-rails`, same module, lockstep
version); the shim `app/javascript/controllers/hibiki_controller.js`
(`export { default } from "hibiki-rails"`) registers it as `hibiki`, which the
helpers hardcode. Importmap apps get the pins `hibiki-rails` and
`hibiki-rails/motion` from the engine; bundler apps `npm add hibiki-rails`
(peers `@hotwired/stimulus >= 3.2`, `@hotwired/turbo-rails >= 8.0`). The
consumer is turbo-rails' own, so islands and streams share one websocket. The
`data-hibiki-*` attributes are private, versioned with the client; never
write them by hand.

## Helpers (`Hibiki::Rails::Helpers`, include it yourself)

| Helper | Returns | Notes |
| --- | --- | --- |
| `hibiki_island(channel, cid:, params: nil)` | `{ data: {...} }` to splat | the primitive; Phlex uses `div(**hibiki_island(...))`; `channel` is a class or string |
| `island(channel, cid: nil, params: nil, transport: :broadcast, tag_name: :div, **attributes) { \|cid\| }` | the root element | ERB-only (needs `capture`; raises elsewhere); class-only; generates a UUID cid; `:broadcast` adds `turbo_stream_from channel.channel_name, cid`; other keywords land on the root, `data:` merged beneath the island's keys |
| `on(action, event: :click, with: nil, debounce: nil, confirm: nil, reset: nil, fallback: nil)` | `{ data: {...} }` to splat | one `event->action` token per event; names must match `/\A[a-z][a-z0-9_.-]*\z/i` |
| `reactive(name, placeholder = "", tag_name: :span)` | a complete element | `<span data-hibiki-value="name">0</span>`; names match `/\A[a-z][a-z0-9_-]*\z/i` |
| `reactive_attrs(name)` | `{ data: { hibiki_value: } }` | the Phlex form: `span(**reactive_attrs(:remaining)) { @remaining.to_s }` |

## `on` options

| Option | Effect |
| --- | --- |
| `event:` | one event or a list: `:click` (default), `:change`, `:input`, `:submit`, or the `:visible` pseudo-event |
| `with:` | a hash merged into every payload from this control |
| `debounce:` | ms to let the gesture settle; `:input` gets 250 by default, `0` sends every keystroke; the payload is built when the action fires, so the last value wins |
| `confirm:` | a `window.confirm` message; declining performs nothing and does not submit; `data-turbo-confirm` is ignored, the control is not Turbo-driven |
| `reset:` | `false` keeps a submitted form's inputs; the default reset runs before the server replies, so an edit form needs `false` |
| `fallback:` | `true` makes the control's native href/action its degraded path (below) |

Payload per gesture: a changed control contributes `name => value` (checkbox:
its checked boolean; multi-select: an array; a `[]`-suffixed name collects
every entry as an array under the bare key); a submitted form contributes its
`FormData`; `with:` merges first, the reserved `hbk` seq last; keys are strings.

`visible`: an `IntersectionObserver` sentinel, always present. It fires once
per observation and re-attaches to the replacement after each swap, so a
load-more control doubles as infinite scroll; pair it with a generation token
in `with:` and no-op on a stale one, since it can fire again before a swap
lands. Never give a `visible` control `fallback:` (off-ready, scrolling into
view would navigate); split it into a `visible`-only wrapper and an inner link
with `click`, a real href, and `fallback: true`.

## Fallback contract

```erb
<%= link_to "Edit", edit_song_path(song.id), **on(:edit, with: { id: song.id }, fallback: true) %>
```

Only a `ready` island intercepts and performs; in any other state the client
stands aside (no `preventDefault`, no queueing) and the browser follows the
markup. A send that fails on a socket believed live runs the native path by
hand (`form.submit()` / `location.assign`). `confirm:` gates the native path
too, and the client copies the `csrf-token` meta into the form's
`authenticity_token` first, because channel-rendered forms have no session.

## Subscribe params

`params:` rides along at subscribe and arrives as `params[:record_id]` beside
`params[:cid]`. It is client-supplied and untrusted: look up inside a scope you
own and `reject` on a miss; never interpolate it into a stream, class, column,
or scope. The client cannot override `channel` or `cid` through it.

```ruby
private

def record_id = @record_id ||= current_user.books.where(id: params[:record_id]).pick(:id)

def subscribed
  return reject unless record_id   # before super: no graph for an unknown id
  super
  return if subscription_rejected?
  stream_from "book:#{record_id}:changed"   # built from the authorized lookup
end
```

## Does an island need a Turbo stream?

| Channel renders with | `turbo_stream_from` in the island | First update |
| --- | --- | --- |
| `broadcast_replace` / `broadcast_morph` / `broadcast_refresh` | yes; `island` writes `turbo_stream_from channel.channel_name, cid` by default | client waits on `streamConnected` before subscribing |
| `transmit({ html: })` / `transmit_value` / `transmit_url` | no; `transport: :transmit` (also for a channel overriding `stream_name`, which writes its own stream line with the yielded cid) | `received` is registered at subscribe, before `build_graph` |

## Transmit message shapes

| Message | Sent by | Client does |
| --- | --- | --- |
| `{ html: }` | your effect (`transmit({ html: ApplicationController.render(...) })`) | swaps each top-level element into the element with the same id; dispatches `hibiki:before-render` first |
| `{ value: { name:, text: } }` | `transmit_value` | sets `textContent` on every `[data-hibiki-value=name]`, document-wide |
| `{ url: }` | `transmit_url` | `history.replaceState`, same-origin only |
| `{ ack:, dropped: }` | `perform_action` | clears busy; handled before `received`, so an override cannot break it |

`hibiki:before-render` bubbles from the island root with
`detail: { island, content, render }`; a listener may replace `detail.render`
with one that waits (the motion module does). Never transmit a fragment holding the input being typed in.

## Exports

| Export | Use |
| --- | --- |
| default / `HibikiController` | the generic island controller; subclass to change `static busyDelay` (150), `busyGrace` (60), `busyCeiling` (10000) |
| `ChannelController` | the base for your own Stimulus shape: `static channel`, `subscribeParams()` (keep `channel`/`cid`), `received(data)` (call `super`), `perform(action, payload)` |
| `performOn(element, action, payload)` | fire an action through the containing island; returns seq or `undefined` |
| `islandFor(element)` | the generic island controller containing the element, or `undefined` |
| `streamConnected(sourceEl)` | promise resolving when a `turbo-cable-stream-source` reports `connected` |

Full docs: https://planetaska.github.io/hibiki/the-js-client/
