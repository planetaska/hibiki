---
title: The JS client
nav_order: 6
---

# The JS client

The gem vendors its own JavaScript, turbo-rails-style: the engine puts `hibiki.js` on the app's asset path and merges the `"hibiki-rails"` pin into the import map, so importmap-rails apps have no install step beyond registering the controller. `bin/rails g hibiki:rails:install` does that (plus the `Helpers` include below, the `ApplicationCable` boilerplate, and the `@rails/actioncable` pin — a stock app has neither until its first `rails g channel`), or create the one-line shim yourself:

```js
// app/javascript/controllers/hibiki_controller.js
export { default } from "hibiki-rails" // registers as "hibiki" — the helpers hardcode that identifier
```

The registration is a file-backed shim on purpose: importmap apps eager-load it from the controllers directory, jsbundling apps get the matching import/register pair in `controllers/index.js` (the install generator appends it), and because it is derived from a real controller file, `bin/rails stimulus:manifest:update` regenerates it instead of dropping it.

For jsbundling/vite apps, `npm install hibiki-rails` — the [npm package](https://www.npmjs.com/package/hibiki-rails) is the same module the engine vendors, and pulls in `@rails/actioncable`. It is released in lockstep with the gem:

| `hibiki_rails` gem | `hibiki-rails` npm | notes |
| ------------------ | ------------------ | ----- |
| 0.10.0             | 0.10.0             | no client change (on the gem side, [`hibiki:rails:upload_field`]({{ "/file-uploads/" | relative_url }}) — attachments on both edit surfaces, `--accept`, `--many` galleries) |
| 0.9.1              | 0.9.1              | no client change (on the gem side, [`hibiki:rails:nested`]({{ "/nested-forms/" | relative_url }}) creates a missing child model from its field list) |
| 0.9.0              | 0.9.0              | `perform` on the island controller becomes public API, with a `performOn` export — [drive an island from your own JavaScript]({{ "/driving-an-island/" | relative_url }}). Also fixes `perform` claiming success (a truthy seq) for an action dropped during an offline gap |
| 0.8.0              | 0.8.0              | `fallback:` — a control's native href/action as its degraded path (stand-aside off-`ready`, dead-socket fallthrough, CSRF freshening) — and `history.replaceState` for the channel's `transmit_url` |
| 0.7.0              | 0.7.0              | a `[]`-suffixed field name collects **all** its FormData entries as an array — a multi-select's full selection reaches the channel |
| 0.6.0              | 0.6.0              | no client change (the AR-equality release on the gem side) |
| 0.5.0              | 0.5.0              | no client change: `@rails/actioncable` becomes a peer dependency (it was double-bundled), and the gem's Rails floor moves to 8.0 |
| 0.4.0              | 0.4.0              | loading and connection state: `data-hibiki-busy`, `aria-busy`, `data-hibiki-state`, the reserved `hbk` payload key, and actions queued until the subscription confirms |
| 0.3.0              | 0.3.0              | `input` + debounce, the `visible` sentinel, event lists, `confirm:`/`reset:`, correct checkbox and multi-select payloads, subscribe params |
| 0.2.0              | 0.2.0              | reactive values (`data-hibiki-value`) |
| 0.1.0              | 0.1.0              | initial release |

Upgrading: the [changelog](https://github.com/planetaska/hibiki-rails/blob/main/CHANGELOG.md) carries the per-release detail. One historical note: **0.3.0 fixed a security issue affecting Rails 7.1 and 7.2 apps only** — channel lifecycle methods were client-invocable there, because the ActionCable hook the gem used to hide them exists on 8.x alone. It matters for 0.4.0 and earlier; from 0.5.0 the gem requires Rails 8.0, so those Rails versions cannot run it at all.

## Islands and helpers

The client is one generic Stimulus controller that drives any *island*: a DOM subtree bound to one channel subscription. Islands are stamped with the opt-in `Hibiki::Rails::Helpers` — include it where you want the bare names (`ApplicationHelper` for ERB, individual Phlex components); the gem never includes it for you:

```erb
<%= tag.div(**hibiki_island(TodosChannel, cid: @cid)) do %>
  <%= render TodoList.new %>  <%# placeholder; replaced by DOM id %>
  <%= tag.form(**on(:add, event: :submit)) do %>
    <input type="text" name="title">
    <button>add</button>
  <% end %>
<% end %>
```

- `hibiki_island(channel, cid:, params:)` — the island root: one subscription, identified by the page's `cid`. See [Subscribe params](#subscribe-params) for `params:`.
- `on(action, event:, with:, debounce:, confirm:, reset:, fallback:)` — forward an event as a channel action. See [Events and modifiers](#events-and-modifiers).
- `reactive(name, placeholder)` / `reactive_attrs(name)` — placeholder for a single reactive value, paired with the channel's `transmit_value` (see [Reactive values]({{ "/reactive-values/" | relative_url }})).

## Events and modifiers

`on` stamps the control with one `event->action` token per event, and the left side of that arrow names an **event** — that is all it ever names. DOM events are a subset: `:click` (the default), `:change`, `:input`, `:submit`, plus the `:visible` pseudo-event. Everything else — how long to wait, whether to ask first, whether to reset — is a separate attribute scoped to the control, so the token list stays parseable by whitespace and one element can answer several events:

```erb
<%= tag.button(**on(:load_more, event: %i[click visible], with: { shown: rows.size })) %>
```

| option | what it does |
| ------ | ------------ |
| `event:` | one event, or a list of them. |
| `with:` | a hash merged into every payload from this control. |
| `debounce:` | milliseconds to let the gesture settle before performing. `:input` gets **250 ms by default** — pass `debounce: 0` to send every keystroke. The payload is built when the action fires, so the last value wins. |
| `confirm:` | a `window.confirm` message. Declining performs nothing (and does not submit the form). Note that `data-turbo-confirm` does *not* work on a hibiki control — it isn't a Turbo-driven form. |
| `reset:` | `false` keeps a submitted form's inputs. The default resets them, which is right for an "add" form and wrong for an edit one: the reset runs synchronously, before the server has replied, so a failed commit would discard what the user typed. |
| `fallback:` | `true` makes the control's own native behavior its degraded path — see [Fallbacks](#fallbacks-the-native-behavior-as-the-degraded-path). |

What a changed control contributes to its payload under its own `name`: a checkbox sends its **checked state** as a boolean, a multi-select sends an **array** of its selected values, everything else sends `value`. A submitted form sends its `FormData`.

`visible` is backed by an `IntersectionObserver`, always present in the client. It fires **once per observation** and re-attaches to the replacement element after each fragment swap, which is what lets a load-more control double as an infinite-scroll sentinel and keep paging when one page didn't fill the viewport. Because an observer can fire again before a swap lands, pair it with a generation token in `with:` and make the action a no-op when the token is stale.

The shape of this helper interface is inspired by [phlex-reactive](https://phlex-reactive.zoolutions.llc)'s `on(...)` actions.

## Fallbacks: the native behavior as the degraded path

`fallback: true` is for a control that already *has* a native behavior — a link with a real `href`, a form with a real `action`:

```erb
<%= link_to "Edit", edit_song_path(song.id),
            **on(:edit, with: { id: song.id }, fallback: true) %>
```

Only a **`ready`** island intercepts the gesture and performs the channel action. In every other state — connecting, offline, stalled — the client stands aside entirely: no `preventDefault`, no queueing, and the browser does exactly what the markup says. This is deliberately *not* the connect-window queue that plain actions get: the destination answers immediately, where a queued gesture would render nothing until the socket recovered.

A socket can also be dead without the client knowing it yet. When a performed action's send reports failure, the client settles the trip and runs the native behavior by hand — `form.submit()` for a form, `location.assign` for a link. The gesture never left the page, so it cannot double-fire.

Two guarantees ride along:

- **`confirm:` gates the native path too.** A destructive submit must not slip past its dialog just because the island happens to be down.
- **Native submits get a fresh CSRF token.** Before letting (or making) a form submit natively, the client copies the `csrf-token` meta value into the form's `authenticity_token` field. This is load-bearing, not an edge case: fragments repainted by a channel are rendered without a session, so every repainted `button_to` form is tokenless — and the first broadcast replaces the first-paint fragment seconds after load. A truly script-free page still holds its first-paint token and needs no help.

The net effect is one set of markup working at three levels: live island, degraded (scripts ran, socket down), and no scripts at all. The generated scaffold leans on this for its New and Edit links, its destroy `button_to`, its controls form and its page control — [CRUD scaffolding]({{ "/crud-scaffolding/" | relative_url }}) shows the pattern in full.

## Subscribe params

`params:` hands the channel values at subscribe time, reaching it as `params[:key]` beside `cid`. It is how a channel learns *which* record its page is about — the subscription is the only server-side hook that runs before the graph is built:

```erb
<%= tag.div(**hibiki_island(BookChannel, cid:, params: { record_id: @book.id })) do %>
```

**They are client-supplied and untrusted, exactly like query params on a request.** Anyone can open a socket and send whatever they like, so a channel may use one only to **look up a record inside a scope it chooses itself**, and must `reject` when that lookup fails:

```ruby
private

def record_id = @record_id ||= current_user.books.where(id: params[:record_id]).pick(:id)

def subscribed
  return reject unless record_id   # before super: no graph for an unknown id

  super
  return if subscription_rejected?

  stream_from "book:#{record_id}:changed"   # built from what the lookup returned
end
```

Never interpolate a param into a streamable name, a class name, a column name, or a scope. The streamable a channel streams from is always derived server-side from the record it has already loaded and authorized — otherwise a client naming its own streamable is reading other people's broadcasts. The client cannot override `channel` or `cid` through `params:`.

## The transmit transport

Transport is the channel's own subscription in both directions: render effects call `transmit({ html: })` and the client swaps each fragment in by its root DOM id (`Hibiki::Phlex.render_effect` pairs naturally):

```ruby
def build_graph
  @list = TodoList.new
  Hibiki::Phlex.render_effect(@list) { |html| transmit({ html: }) }
end
```

Because the client registers its `received` callback at subscribe time — before the server ever runs `build_graph` — the effects' first transmits always land: no Turbo stream, no connected-wait, and the server-rendered initial HTML only fills the space until the first transmit arrives. One rule carries over from any replace-fragment design: never transmit a fragment containing the input the user is currently typing in.

For gestures that can't be declared in markup — a drag library's drop callback, a canvas widget, a keyboard shortcut — `perform`/`performOn` fire an action through the island's own subscription from your own code: see [Driving an island from JS]({{ "/driving-an-island/" | relative_url }}).
