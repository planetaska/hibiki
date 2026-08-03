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
| 0.4.0              | 0.4.0              | loading and connection state: `data-hibiki-busy`, `aria-busy`, `data-hibiki-state`, the reserved `hbk` payload key, and actions queued until the subscription confirms |
| 0.3.0              | 0.3.0              | `input` + debounce, the `visible` sentinel, event lists, `confirm:`/`reset:`, correct checkbox and multi-select payloads, subscribe params |
| 0.2.0              | 0.2.0              | reactive values (`data-hibiki-value`) |
| 0.1.0              | 0.1.0              | initial release |

Upgrading: the [changelog](https://github.com/planetaska/hibiki-rails/blob/main/CHANGELOG.md) carries the per-release detail. **0.3.0 fixes a security issue affecting Rails 7.1 and 7.2 apps only** — channel lifecycle methods were client-invocable there, because the ActionCable hook the gem used to hide them exists on 8.x alone.

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
- `on(action, event:, with:, debounce:, confirm:, reset:)` — forward an event as a channel action. See [Events and modifiers](#events-and-modifiers).
- `reactive(name, placeholder)` / `reactive_attrs(name)` — placeholder for a single reactive value, paired with the channel's `transmit_value` (see [Reactive values]({{ "/reactive-values/" | relative_url }})).

## Events and modifiers

The left side of `->` names an **event**, and that is all it ever names. DOM events are a subset: `:click` (the default), `:change`, `:input`, `:submit`, plus the `:visible` pseudo-event. Everything else — how long to wait, whether to ask first, whether to reset — is a separate attribute scoped to the control, so the token list stays parseable by whitespace and one element can answer several events:

```erb
<%= tag.button(**on(:load_more, event: %i[click visible], with: { shown: rows.size })) %>
```

| option | what it does |
| ------ | ------------ |
| `event:` | one event or a list. A list stamps one `event->action` token each. |
| `with:` | a hash merged into every payload from this control. |
| `debounce:` | milliseconds to let the gesture settle before performing. `:input` gets **250 ms by default** — pass `debounce: 0` to send every keystroke. The payload is built when the action fires, so the last value wins. |
| `confirm:` | a `window.confirm` message. Declining performs nothing (and does not submit the form). Note that `data-turbo-confirm` does *not* work on a hibiki control — it isn't a Turbo-driven form. |
| `reset:` | `false` keeps a submitted form's inputs. The default resets them, which is right for an "add" form and wrong for an edit one: the reset runs synchronously, before the server has replied, so a failed commit would discard what the user typed. |

What a changed control contributes to its payload under its own `name`: a checkbox sends its **checked state** as a boolean, a multi-select sends an **array** of its selected values, everything else sends `value`. A submitted form sends its `FormData`.

`visible` is backed by an `IntersectionObserver`, always present in the client. It fires **once per observation** and re-attaches to the replacement element after each fragment swap, which is what lets a load-more control double as an infinite-scroll sentinel and keep paging when one page didn't fill the viewport. Because an observer can fire again before a swap lands, pair it with a generation token in `with:` and make the action a no-op when the token is stale.

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

Because the client registers its `received` callback at subscribe time — before the server ever runs `build_graph` — the effects' first transmits always land: no Turbo stream, no connected-wait, and the server-rendered initial HTML is only a paint-avoidance placeholder. One rule carries over from any replace-fragment design: never transmit a fragment containing the input the user is currently typing in.

## Loading and connection state

Every reactivity in this stack is server-side, so every gesture is a round trip. The client stamps what it knows about that trip on the island; turning those attributes into something a user can see is CSS the app owns.

```
island root      data-hibiki-busy      present while an action is in flight
                 aria-busy="true"      the same fact, for assistive tech
                 data-hibiki-state     connecting | ready | offline | stalled
firing control   data-hibiki-busy      on the control that started it
```

These are the **client-written half** of the `data-hibiki-*` protocol — the first attributes in it that no Ruby helper emits. They are stamped at runtime and are **read-only to app code**: app CSS is their whole audience. The rule that the attributes the helpers *do* emit are a private contract you never hand-write is unchanged; this is the other direction.

Everything you want out of them is a descendant selector, which is why the whole feature is one CSS-addressable flag rather than a rendering fork:

```css
[data-hibiki-busy] .spinner        { display: inline-block }
[data-hibiki-state="offline"] .offline-note { display: inline }
```

Two details make those selectors precise. The island root is the only element that ever carries `data-hibiki-state`, so `[data-hibiki-state][data-hibiki-busy]` means "this island is busy" while `[data-hibiki-busy]:not([data-hibiki-state])` means "this control is". And the element that fires a `submit` is the **form**, not the button inside it, so reach for a descendant selector rather than a child one.

### The states

| State | When | What it means to the reader |
| --- | --- | --- |
| `connecting` | Painted, subscription not confirmed | Content is real but **inert** |
| `ready` | Subscription confirmed | Normal |
| `offline` | Socket dropped, ActionCable retrying | Content is **frozen**, and nothing else would say so |
| `stalled` | A trip outlived `busyCeiling` | We lost it — said plainly rather than cleared silently |

`connecting` is stamped **synchronously** as the controller connects, before the subscription is even opened, so an island can be dimmed for the whole window rather than from the middle of it.

Note what is *not* in that table: a first-paint loading state. There is no such moment. The controller server-renders real content, and every later update replaces valid content with newer valid content — so during a round trip what is on screen is **stale, not absent**. Annotate the stale thing; don't swap it for a skeleton.

### Actions performed before the subscription confirms

ActionCable's `Subscription#perform` silently returns false on a socket that isn't open yet, and on the Turbo-broadcast path the window before confirmation is about three serialised round trips — tens of milliseconds on localhost, about a second on a real link. Clicks in that window used to vanish.

They are now **queued and flushed** when the server confirms the subscription.

That covers the **first connect window only**. Once the link has been up, a gap means the socket dropped — and reconnecting builds a *fresh* graph server-side with default state, so replaying intent formed against the old one is worse than dropping it. Across that gap the island reads `offline` for the whole duration, which is the signal the connect window cannot give: there, the page is painted and looks live.

### `hbk`, and the ack

Every perform carries a sequence number under the reserved key **`hbk`**, stamped last so a form field can never overwrite it. (It is the second reserved payload key — ActionCable's own `Subscription#perform` already writes `action`.) The server acknowledges that sequence once the action's batch has run, and the ack is what clears the indicator.

It has to be an ack rather than "clear when a render lands", because **an action can legitimately produce zero bytes**: hibiki re-runs an effect only when a value it read actually changed, so an ordinary gesture may correctly render nothing at all.

The ack is intercepted in the base's own subscription handler, *before* `received` — so a `ChannelController` subclass that overrides `received` without calling `super` still clears.

### Tuning

Three class properties are the entire tuning surface. There is deliberately no Stimulus value and no helper option, so an island stamps nothing about them and the Ruby surface stays unchanged:

| Property | Default | What it is |
| --- | --- | --- |
| `busyDelay` | 150 ms | How long a trip has to take before it is worth mentioning. A localhost trip is 18–25 ms, so this suppresses that flicker outright. |
| `busyGrace` | 60 ms | How long to wait after an ack for a broadcast still in flight. The ack travels the island's own socket; a broadcast takes a pubsub hop. |
| `busyCeiling` | 10000 ms | When to call a trip stalled rather than clear it silently. |

To change them, subclass and re-register through `hibiki_controller.js`:

```js
import { HibikiController } from "hibiki-rails"

class SlowLink extends HibikiController {
  static busyDelay = 400
}

export default SlowLink
```

### Two things this is not

**Not optimistic UI.** Svelte can update before the server answers because the client owns the state; hibiki deliberately does not. Pending feedback *is* the substitute.

**Not a per-action response.** The graph is not request/response — an effect may fire long after the action that triggered it, or not at all. The ack is a **batch boundary**: it says "your action ran", not "here is its result".

For a worked example of all of this — five sites, three CSS variants, in a file you own — see the loading section of [CRUD scaffolding]({{ "/crud-scaffolding/" | relative_url }}).
