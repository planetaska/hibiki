---
title: Loading state
nav_order: 4
---
# Loading and connection state

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

| State        | When                                 | What it means to the reader                            |
| ------------ | ------------------------------------ | ------------------------------------------------------ |
| `connecting` | Painted, subscription not confirmed  | Content is real but **inert**                          |
| `ready`      | Subscription confirmed               | Normal                                                 |
| `offline`    | Socket dropped, ActionCable retrying | Content is **frozen**, and nothing else would say so   |
| `stalled`    | A trip outlived `busyCeiling`        | We lost it — said plainly rather than cleared silently |

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

| Property      | Default  | What it is                                                   |
| ------------- | -------- | ------------------------------------------------------------ |
| `busyDelay`   | 150 ms   | How long a trip has to take before it is worth mentioning. A localhost trip is 18–25 ms, so this suppresses that flicker outright. |
| `busyGrace`   | 60 ms    | How long to wait after an ack for a broadcast still in flight. The ack travels the island's own socket; a broadcast takes a pubsub hop. |
| `busyCeiling` | 10000 ms | When to call a trip stalled rather than clear it silently.   |

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

For a worked example of all of this — five sites, three CSS variants, in a file you own — see the loading section of [CRUD scaffolding notes]({{ "/crud-notes/" | relative_url }}).
