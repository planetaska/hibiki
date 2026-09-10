---
title: Motion explained
nav_order: 9
---

# Motion explained

A `hibiki_rails` page never changes itself. The state lives on the
server, and every change reaches the browser as a re-rendered piece of
HTML, which the gem's JS client swaps into the page in place of the old
one (see [The JS client]({{ "/the-js-client/" | relative_url }})). That
is fine for content and awkward for certain animations. Take a row that
should slide out when it is destroyed: the moment the new HTML lands,
the row is no longer on the page, and there is nothing left to slide out.

Elements that enter have no such problem. CSS on its own can give a
newly inserted element an opening look and run a transition from there
to its normal look. Elements that leave need help: something must hold
the new HTML back until the old element has finished its transition,
and only then let the swap run. The `hibiki-rails/motion` module
provides such functionality. This page describes the contract between
the module and your application's CSS.

If you generated your pages with the scaffold, all of this is already
on, and [Adding motion]({{ "/adding-motion/" | relative_url }}) shows how
to change what the scaffold wrote and animate an element of your own.
This page explains what is happening underneath.

## A first example

Three things make an element animate. The module is imported once, the
element carries a `data-motion` attribute and an `id`, and your CSS says
what the motion looks like. Here is a note that drops in when it
appears and drops out when it leaves, in plain CSS:

```js
// app/javascript/application.js
import "hibiki-rails/motion"
```

```erb
<div id="note_<%= note.id %>" data-motion class="note">
  ...
</div>
```

```css
.note                      { transition: opacity 300ms, translate 300ms }
.note[data-motion-leaving] { opacity: 0; translate: 0 1rem }
@starting-style {
  .note                    { opacity: 0; translate: 0 1rem }
}
```

The first rule says which properties animate and how long they take.
The second describes the note as it leaves. When a re-render is about
to remove the note, the module sets `data-motion-leaving` on it, this
rule fades it out and moves it down, and the module waits for that
transition to end before it lets the swap run. The third rule handles
the entrance, and needs no help from the module. `@starting-style` is a
CSS feature that gives an element its styles for the instant it is
inserted, and the transition then runs from those to the element's
normal styles. The note appears faded and low, and settles into place.

The import line is the same in every app. The engine pins
`hibiki-rails/motion` for importmap apps, and the npm package exposes
the same path for bundlers. The scaffold adds the line for you. Without
it, a marked element still works: it appears and disappears at once.

The `id` is required because the module tells a leaving element from a
staying one by comparing ids. An element on the page whose id is missing
from the incoming HTML is leaving. That is the same rule the client uses
to decide which element a fragment replaces.

## The attributes

Four attributes make up the contract. You write two, and the module
writes two. All four are public, and yours to use in markup and CSS.
That sets them apart from the `data-hibiki-*` attributes the Ruby helpers
emit, which are a private contract between the helpers and the client.

| Written by | Attribute | Meaning |
| --- | --- | --- |
| you | `data-motion` | Animate this element when it leaves, and mark it while it enters |
| you | `data-motion="own"` | Animate the leave only when a gesture inside this element removed it ([below](#leaving-only-on-the-users-own-gesture)) |
| the module | `data-motion-leaving` | Present from the moment a re-render would remove the element until its transitions end |
| the module | `data-motion-entering` | Present from the moment a re-render inserted the element until its first transitions end |

Plain CSS reaches the two module-written attributes with attribute
selectors, as in the example above. Tailwind reaches them with variants:
`data-motion-leaving:` on the element itself, `in-data-motion-leaving:`
on a descendant of a leaving element, and `starting:`, which is
Tailwind's spelling of `@starting-style`, for the entrance.

## How a leave works

Re-rendered HTML reaches the page by one of two routes. A Turbo stream
broadcast arrives through Turbo, and a transmit message arrives through
hibiki's own client;
[the transmit transport]({{ "/the-js-client/" | relative_url }}#the-transmit-transport)
section of The JS client compares the two. Both routes fire an event just
before the swap, and the module listens for both: Turbo's
`turbo:before-stream-render`, and `hibiki:before-render`, which the client
dispatches for the same purpose.

When the event fires, the module compares the marked elements on the
page with the ids in the incoming HTML. Each marked element the incoming
HTML lacks gets `data-motion-leaving`, and your CSS responds by starting
a transition. The module waits for the element's transitions to finish
and only then lets the swap run. The swap removes the element, which by
then has finished sliding, fading, or whatever your CSS chose.

A few rules keep the hold honest:

- Renders run in the order they arrive. A render that is being held
  never lets a later one overtake it.
- Every wait gives up after one second, so a transition that never ends
  cannot stall the page.
- A hidden tab waits for nothing. Browsers run no transitions in a
  hidden tab, so the swap runs at once.
- Only the outermost marked element of a subtree animates. A marked
  element inside a leaving one leaves with its parent.
- Only a stream action that removes content is held: `replace`,
  `update`, and `remove`. An `append` or a `prepend` runs at once.

## How an enter works

The entrance needs no help from the module, as the first example
showed: `@starting-style` gives the inserted element its opening styles,
and the transition runs from there. The module adds one thing. It sets
`data-motion-entering` on the element while that first transition runs,
so a rule that should apply only during the motion has something to
match. The scaffold needs this for `overflow: hidden`. Its inline edit
form should be clipped while it grows, but the form holds a dropdown
that is absolutely positioned, and a clip that stayed would cut the
dropdown off.

One rule follows from how a Turbo stream lands. The scaffold's
broadcasts are *morphs*: instead of replacing the old fragment wholesale,
Turbo walks the old tree and the new one together, pairs each element
with its counterpart, and rewrites the paired elements in place. It
pairs by `id` first, and by tag name when there is no id. A rewritten
element was never inserted, so `@starting-style` never fires for it. So
the element that should animate in must carry an id of its own, and the
element it replaces must carry a different one. Then Turbo swaps one for
the other instead of morphing one into the other. The scaffold's row
keeps its display markup in `<div id="book_7_display">` and its edit form
in `<div id="book_7_edit">` for exactly this reason. A bare `<div>` in
either place would be paired with the other and would never animate.

## Leaving only on the user's own gesture

A row can leave a list for several reasons: the user destroyed it,
filtered it out, or paged past it, or someone else destroyed it in
another tab. A slide is right for the first and wrong for the rest. A
filter that slides twenty rows shut one after another is a slower page,
not a nicer one, and a row that vanishes under someone else's gesture
has nothing to announce.

`data-motion="own"` draws that line. The element animates its leave only
when the control that fired the removing action sits inside it: the
row's own Destroy button, or its inline form. The module learns this
from the island, the region of the page bound to one channel
subscription, which records the control behind each action it sends. No
attribute on the control is needed, and a destroy that completes quickly
still counts, even when it finishes before the loading indicator would
have shown. The scaffold marks rows `own` and everything else plain.

## The ready-made transitions

Under the Tailwind and daisyUI variants, the scaffold writes
`app/assets/stylesheets/hibiki_motion.css` once per app. The file
defines each transition as a Tailwind utility class, and the views carry
the class names. The timing lives in the file, so tuning a duration or
an easing is one edit in one place.

| Class | Effect | Parameters |
| --- | --- | --- |
| `hbk-slide` on the box, `hbk-slide-body` on its child | Slides open on insertion and shut on removal, by height. The child's padding collapses with it, and so does the margin a `space-y-*` list gives it | — |
| `hbk-slide-x` on a wrapper, `hbk-slide-x-body` on the card inside | The card slides left and fades, then the wrapper closes the gap. For a removal only; the shape of a swipe-to-delete | — |
| `hbk-fade` | Opacity | — |
| `hbk-fly` | Position and opacity | `--hbk-fly-x`, `--hbk-fly-y` |
| `hbk-scale` | Size and opacity | `--hbk-scale` |
| `hbk-blur` | Blur and opacity | `--hbk-blur` |

The two slides come in pairs because a transition cannot run to a
height the browser works out for itself. The outer element is a grid
whose single row grows from nothing to the size of its content, and the
inner element collapses its padding along with it. The sideways slide
is a pair for a second reason: one element cannot both slide away and
be the box whose height closes the gap.

Only the two slides animate height. The other four leave the
neighbours jumping into the space. Svelte's transitions of the same
names behave the same way without `animate:flip`.

A class can be tuned on one element without touching the file. A
duration utility beside the class name overrides the duration, and a
custom property in square brackets sets a parameter:

```erb
<div id="note_<%= note.id %>" data-motion class="hbk-fade duration-500">
<div id="toast" data-motion class="hbk-fly [--hbk-fly-y:2rem]">
```

That works because the file declares each class with Tailwind's
`@utility` directive rather than as a plain class. The directive places
the rules in Tailwind's utilities layer, above daisyUI's component
styles, so a `.card` on the same element cannot override the slide's
`display`. And Tailwind orders a utility that sets several properties
before one that sets a single property, which is why `duration-500`
wins over the duration inside `hbk-fade`.

Two consequences of `@utility` are worth knowing. Tailwind emits a
utility only where it sees the name in your content, so rebuild the
stylesheet after adding a class name to a view, as the post-install
output's `css` notice says. And the `in-*` variant the slides use needs
Tailwind 4.1 or later.

## Without Tailwind

The `--css=none` variant writes no motion at all, on the reasoning that
an app styling by hand will wire motion the same way it wires everything
else. The contract is small enough to write directly, and the
[first example](#a-first-example) is the whole of it: mark the element,
give it an id, and write three rules. A slide by height takes more CSS
than a fade, for the reason given above. The grid trick in
`hibiki_motion.css` translates to plain CSS line for line if you want it.

## Bringing your own animation

`hibiki_rails` ships the module and the stylesheet so that a generated
page animates with no animation code of your own. Neither is required.
The contract has two seams, and an animation solution of your own can
use either.

**Keep the module and write your own CSS.** The module does not read
`hibiki_motion.css`. It sets the two attributes and waits for whatever
animations the element runs, through the browser's `getAnimations()`,
which covers CSS transitions, keyframe animations, and animations
started with the Web Animations API. Write rules against
`data-motion-leaving` and `@starting-style` in any stylesheet, delete
the generated file, or keep only the effects you use. The render queue,
the one-second ceiling, and the outermost-element rule still apply.

**Leave the module out and hold the swap yourself.** Both routes fire an
event before the swap and carry the swap in `event.detail.render`. A
listener may replace that function with one that returns a promise, and
the client waits for the promise. Turbo's `turbo:before-stream-render`
works this way, and `hibiki:before-render` follows the same shape for
the transmit swap. Any code that can wrap a DOM change can hold the swap
there. For example, this runs every transmit swap inside a view
transition:

```js
document.addEventListener("hibiki:before-render", (event) => {
  const render = event.detail.render
  event.detail.render = () => document.startViewTransition(render).finished
})
```

The Turbo listener is the same, except that its `render` takes the
stream element as an argument, so pass it through:

```js
document.addEventListener("turbo:before-stream-render", (event) => {
  const render = event.detail.render
  event.detail.render = (streamElement) =>
    document.startViewTransition(() => render(streamElement)).finished
})
```

An animation library works the same way when its animation resolves a
promise. The listener decides which elements are leaving, animates them,
waits, and then runs the swap. This one uses GSAP, whose tweens can be
awaited, on elements the app marks `data-leave`:

```js
import gsap from "gsap"

document.addEventListener("hibiki:before-render", (event) => {
  const { content, render } = event.detail
  event.detail.render = async () => {
    const incoming = new Set([...content.querySelectorAll("[id]")].map((el) => el.id))
    const leaving = [...document.querySelectorAll("[data-leave]")].filter((el) => !incoming.has(el.id))
    if (leaving.length) await gsap.to(leaving, { x: -40, opacity: 0, duration: 0.3 })
    render()
  }
})
```

The motion module is itself a listener on these two events. Its source
is
[hibiki-motion.js](https://github.com/planetaska/hibiki-rails/blob/main/app/assets/javascripts/hibiki-motion.js),
and the `held` function there is the whole hold: it marks the leaving
elements, waits for their animations, runs the render, and then marks
the entering ones.

## Limits

- Only Turbo stream renders and transmit swaps are held. A page morph
  from Turbo Drive, such as a page refresh, replaces the page without
  asking, and marked elements it removes vanish at once.
- The module waits for the marked element's own animations, not those
  of its descendants. An animation on the element itself that never
  ends, such as a pulsing background, makes every removal wait out the
  one-second ceiling. Put spinners and pulses on children.
- `own` needs the gesture records of an island, and how the module
  finds the island depends on the route. For a Turbo stream it looks up
  from the target element, and that lookup knows only generic islands,
  the kind the `hibiki` Stimulus controller drives. Under a
  `ChannelController` subclass it finds nothing, so an `own` mark never
  animates a leave that a stream removes; a plain `data-motion` still
  does. Over the transmit transport the client's own event names the
  subclass as the island, so its `own` marks work once it calls
  `trackControl` for its gestures.
- The scaffold's `--skip-motion` leaves every trace out: no stylesheet,
  no import, no marks. See
  [CRUD notes]({{ "/crud-notes/" | relative_url }}#motion) for what the
  generated views carry.
