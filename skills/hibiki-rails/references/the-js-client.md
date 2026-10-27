# The JS client

The gem vendors `hibiki.js` (npm `hibiki-rails`, same module, lockstep
version); the shim `app/javascript/controllers/hibiki_controller.js`
(`export { default } from "hibiki-rails"`) registers it as `hibiki`, which the
helpers hardcode. Importmap apps get the pins `hibiki-rails`,
`hibiki-rails/motion` and `hibiki-rails/commands` (the module that runs `js`
command lists; see commands.md) from the engine; bundler apps `npm add hibiki-rails`
(peers `@hotwired/stimulus >= 3.2`, `@hotwired/turbo-rails >= 8.0`). The
consumer is turbo-rails' own, so islands and streams share one websocket. The
`data-hibiki-*` attributes are private, versioned with the client; never
write them by hand.

## Helpers (`Hibiki::Rails::Helpers`, include it yourself)

| Helper | Returns | Notes |
| --- | --- | --- |
| `hibiki_island(channel, cid:, params: nil)` | `{ data: {...} }` to splat | the primitive; Phlex uses `div(**hibiki_island(...))`; `channel` is a class or string |
| `island(channel, cid: nil, params: nil, transport: :broadcast, tag_name: :div, **attributes) { \|cid\| }` | the root element | ERB-only (needs `capture`; raises elsewhere); class-only; generates a UUID cid; `:broadcast` adds `turbo_stream_from channel.channel_name, cid`; other keywords land on the root, `data:` merged beneath the island's keys |
| `on(action, event: :click, with: nil, debounce: nil, confirm: nil, reset: nil, fallback: nil, replaceable: nil)` | `{ data: {...} }` to splat | one `event->action` token per event; names must match `/\A[a-z][a-z0-9_.-]*\z/i`; `action` may be a `js` command list instead (commands.md) |
| `js` | an empty command list | chain commands on it and hand it to `on` (commands.md, since 0.20.0) |
| `modal(open:)` | `{ data: {...} }` to splat | on a `<dialog>`: the client calls `showModal()` or `close()` to match after each render (commands.md, since 0.20.0) |
| `reactive(name, placeholder = "", tag_name: :span)` | a complete element | `<span data-hibiki-value="name">0</span>`; names match `/\A[a-z][a-z0-9_-]*\z/i` |
| `reactive_attrs(name)` | `{ data: { hibiki_value: } }` | the Phlex form: `span(**reactive_attrs(:remaining)) { @remaining.to_s }` |
| `props(indeterminate:, scroll_top:, scroll_left:, key: nil)` | `{ data: {...} }` to splat | DOM properties that have no attribute (below); any other name raises `ArgumentError` |
| `focus(select: false)` | `{ data: {...} }` to splat | the cursor in a field that a render opens (below); `select: true` also selects its text |

## `on` options

| Option | Effect |
| --- | --- |
| `event:` | one event or a list: `:click` (default), `:change`, `:input`, `:submit`, a key such as `"keydown.esc"` (below), the `:visible` pseudo-event, `:popstate` on the island root (Back and Forward, reactive-values.md), or a dialog's `:cancel` and `:close` (commands.md) |
| `with:` | a hash merged into every payload from this control |
| `debounce:` | ms to let the gesture settle; `:input` gets 250 by default, `0` sends every keystroke; the payload is built when the action fires, so the last value wins |
| `confirm:` | a `window.confirm` message; declining performs nothing and does not submit; `data-turbo-confirm` is ignored, the control is not Turbo-driven |
| `reset:` | `false` keeps a submitted form's inputs; the default reset runs before the server replies, so an edit form needs `false` |
| `fallback:` | `true` makes the control's native href/action its degraded path (below) |
| `replaceable:` | `true` holds a send while an action of its kind (name and payload keys) from the island waits for its ack; a newer one replaces it, and any other action sends it first (since 0.21.0, replaceable-actions.md) |

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

Unsent typing (since 0.17.0): a field with a pending debounced `:input`
keeps its typed text and caret through any render until the send fires; after
that the server's value wins, so Reset and a failed save still overwrite it.
An undebounced action first sends the island's pending debounced input, so
Enter straight after the last keystroke saves the whole text. A field that
sends only on `change` or `submit` is not kept: send each input when a form
must keep its typing. Checkboxes, radios, file inputs, and multi-selects are
not recorded.

## Keys in `on` (since 0.17.0)

```erb
<%= tag.div(**on(:cancel, event: "keydown.esc")) do %>
  <%= tag.form(**on(:save, event: :submit, reset: false)) do %> ... <% end %>
<% end %>
<%= link_to "New song", new_song_path,
      **on(:new_form, event: ["click", "keydown.n@window"]) %>
```

| Token | Heard |
| --- | --- |
| `keydown.<key>` | while focus is inside the element; the client walks up from the focused element to the nearest element declaring that key |
| `keydown.<key>@window` | anywhere on the page while the element is rendered, hidden or not; in a text field, select, or editable element only `esc` and `ctrl`/`meta` combinations fire |

- Keys: a letter, a digit, or `enter tab esc space up down left right home
  end page_up page_down`.
- Modifiers: `ctrl`, `meta`, `shift`, in front and joined by `+`
  (`keydown.meta+shift+k`), matched exactly: `keydown.s` does not fire on
  Ctrl+S. No `alt`. Cmd-or-Ctrl is two tokens:
  `event: ["keydown.ctrl+s", "keydown.meta+s"]`.
- An unknown key or modifier, `shift` with a digit, and a bare `keydown`
  raise `ArgumentError` at render. Typed text is `:input`.
- A matched key's default is prevented. IME composition and a held key's
  repeats send nothing.
- The payload is `with:` only; `confirm:`, `debounce:`, and the busy mark
  apply as to a click.
- One element takes one action: a form wired for `submit` cannot also send
  `cancel` on Escape. Put the key on a wrapper.
- A key without a scope needs focus inside its element; `focus` puts it
  there when a form opens.

## `focus`: the cursor in an opened field (since 0.17.0)

```erb
<%= text_field_tag "title", form.title, **focus(select: true) %>
```

The client focuses a marked element:

- once, on the render that brings it; later renders that keep it do nothing;
- only on a render this tab's own action caused, never on another visitor's
  save or a `broadcast_refresh`;
- never on page load (use `autofocus` there), and never away from a field
  with unsent typing.

The element must be inside an island. Merge with `on` as `props` does:
`on(:set_field, event: :input).deep_merge(focus)`, or `mix` in Phlex.

Focus return needs no markup. When a render removes the focused element, the
client focuses, in order:

1. the element with the same id, caret included (every id-bearing field under
   transmit, which replaces elements on each render);
2. the control that opened the form, if the form's field carries `focus`
   (found again by id, or by its action and `with:` payload);
3. the first control inside the nearest id-bearing ancestor still on the page.

Only a control takes focus, never a container; with no target (a destroyed
row) focus stays where the browser put it. It applies to every render on both
transports and never moves focus the visitor has since put elsewhere. Scaffolded
forms carry no `focus`, so they get 1 and 3 only; add `focus` to a generated
form's first field for the cursor on open and the return to Edit or New.

A marked field inside a closed `<dialog>` does not count as on the page
(since 0.20.0): it takes the cursor on the render that opens the dialog, and
focus returns to the opener when the dialog closes.

## `props`: DOM properties (since 0.16.0)

A checkbox's `indeterminate` and a container's scroll position exist only as
DOM properties, so a fragment cannot carry them. `props` writes them beside
the element's attributes; the client assigns them when the island connects
and after every render (transmit swap, Turbo stream, Turbo page refresh).
The channel needs nothing new: it re-renders the fragment as usual.

```erb
<%= check_box_tag "all", "1", all_selected,
      **on(:select_all, event: :change)
          .deep_merge(props(indeterminate: some_selected)) %>
<%= tag.div class: "list", **props(scroll_top: 0, key: page) do %>
```

| Property | Value | Assigned |
| --- | --- | --- |
| `indeterminate:` | truthy/falsy, always emitted | after every render, so the server's value wins over a click (the browser clears it on click) |
| `scroll_top:`, `scroll_left:` | a finite number; `nil` omits it | to a new element, and again only when the helper's output changes; the visitor's own scrolling survives other renders |
| `key:` | any JSON value | never assigned; it only changes the output, so `scroll_top: 0, key: page` scrolls to the top on each page change |

- `on` and `props` both return a `data:` hash, and two splats keep only the
  second. Use `on(...).deep_merge(props(...))`, or `mix(on(...), props(...))`
  in Phlex.
- The element must be inside an island and be part of a fragment the channel
  re-renders, or its property never changes after first paint.
- The client ignores names outside the list, so a fragment cannot set
  `innerHTML` or a handler.
- State with an attribute (`value`, `checked`, `disabled`, `<details open>`)
  needs no helper. Method calls (`showModal()`, `play()`) are not covered;
  they need JavaScript of your own. Focus has its own helper (above).

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
| `{ url: }` | `transmit_url` | `history.replaceState`, same-origin only; with `push: true` (`history: :push`) a history entry when it answers this tab's action |
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
