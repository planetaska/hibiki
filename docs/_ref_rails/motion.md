---
title: Motion
nav_order: 9
---

# Motion

Every change to a live list arrives as a re-rendered fragment, and the
page merges it in place. A row you destroyed is simply gone in the next
paint. There is no moment for it to slide out, because the element that
would slide has already been removed when the browser next draws. Motion
therefore needs two things. Entering elements need a *from* state on the
frame they appear, which CSS can supply on its own. Leaving elements need
someone to hold the render until their transition has finished. The
motion module does the holding, and this page describes the contract
between it and your CSS.

The scaffold turns all of this on for you: the create form and the
inline edit form slide open and shut, and a row you destroy slides out
to the left before the list closes the gap. Read on when you want to
animate something of your own, tune what the scaffold wrote, or
understand what is happening under it.

## Turning it on

Three pieces, in the order the browser meets them:

1. Import the module once, beside your controllers:

   ```js
   // app/javascript/application.js
   import "hibiki-rails/motion"
   ```

   The engine pins `hibiki-rails/motion` for importmap apps, and the npm
   package exposes the same path for bundlers. The scaffold adds the
   line for you.

2. Mark each element that should animate with `data-motion`. The
   element needs an `id`: the module tells leaving from staying elements
   by id, the same way the transports tell fragments apart.

3. Give the element a transition. With Tailwind, the scaffold's
   `hibiki_motion.css` names ready-made ones (below); without it, a few
   lines of plain CSS do (also below).

Without the import, marked elements still work. They pop instead of
sliding.

## The contract

Two attributes are yours to write, two are written by the module. All
four are public, unlike the `data-hibiki-*` attributes the helpers emit.

| Written by | Attribute               | Meaning                                                               |
| ---------- | ----------------------- | --------------------------------------------------------------------- |
| you        | `data-motion`           | Animate this element's leave; bracket its enter                        |
| you        | `data-motion="own"`     | Animate the leave only when the gesture that removed it came from inside it |
| the module | `data-motion-leaving`   | Set on a marked element the incoming render lacks, until its transitions end |
| the module | `data-motion-entering`  | Set on a marked element the render inserted, until its first transitions end |

CSS reaches them with attribute selectors, or with Tailwind's variants:
`data-motion-leaving:` on the element itself, `in-data-motion-leaving:`
on a descendant, and `starting:` for the entering state.

## How a leave works

When a render arrives, the module compares the marked elements on the
page with the ids in the incoming fragment. Each marked element the
fragment lacks gets `data-motion-leaving`. The module then waits for that
element's own transitions to finish and lets the render run. The render
removes the element, which has by then finished sliding, fading, or
whatever your CSS chose.

Renders queue in the order they arrive, so a held render never lets a
later one overtake it. A hidden tab waits for nothing, since its frames
never come. Every wait races a one-second ceiling, so a tab hidden in
the middle of a hold cannot stall the queue. Only the outermost marked
element of a subtree moves; a marked element inside a leaving one is
left to leave with its parent.

Both transports hold: Turbo streams, through the `turbo:before-stream-render`
event, and hibiki's own transmit swap, through the `hibiki:before-render`
event the client dispatches for the same purpose. Only stream actions
that remove content hold. An append or a prepend runs at once.

## How an enter works

The enter needs no help from the module. `@starting-style` gives an
inserted element its first-frame values, and the transition runs from
there to the element's resting styles. The module only brackets that
first transition with `data-motion-entering`, so that something like
`overflow: hidden` can apply while the element grows and be gone from its
resting state. The scaffold needs that: its inline form holds a dropdown
that is absolutely positioned, and a clip that stayed would cut it off.

One rule follows from how the page is merged. The merge pairs elements by
id and, failing that, by tag, and it rewrites a paired element in place
rather than inserting a new one. `@starting-style` fires only on a real
insertion. So the element that swaps in must carry an id of its own, and
the element it replaces must carry a different one. The scaffold's row
keeps its display markup in `<div id="book_7_display">` and its edit form
in `<div id="book_7_edit">` for exactly this reason. A bare `<div>` in
either place would be paired with the other and would never animate.

## The `own` policy

A row can leave a list for several reasons: you destroyed it, you
filtered it out, you paged past it, or someone else destroyed it in
another tab. Sliding is right for the first and wrong for the rest. A
filter that slides twenty rows shut one after another is a slower page,
not a nicer one, and a row that vanishes under someone else's gesture
has nothing to announce.

`data-motion="own"` draws that line. The element animates its leave
only when the control that fired the removing action sits inside it:
the row's own Destroy button, or its inline form. The module reads that
from the island's record of the trip, so no attribute on the control is
needed, and a fast local destroy still counts even when it finishes
before the busy indicator would have shown. The scaffold marks rows
`own` and everything else plain.

## The class names

`hibiki_motion.css`, written once per app, names each transition as a
Tailwind utility. The views carry the names, and the file carries the
timing, so tuning a duration or an easing means editing one line in one
file.

| Class | Effect | Parameters |
| --- | --- | --- |
| `hbk-slide` on the box, `hbk-slide-body` on its child | Slides open on insertion and shut on removal, by height. The child's padding collapses with it, and a `space-y-*` list's margin goes with it too | — |
| `hbk-slide-x` on a wrapper, `hbk-slide-x-body` on the card inside | The card slides left and fades, then the wrapper closes the gap. For a removal only; the shape of a swipe-to-delete | — |
| `hbk-fade` | Opacity | — |
| `hbk-fly` | Translate and opacity | `--hbk-fly-x`, `--hbk-fly-y` |
| `hbk-scale` | Scale and opacity | `--hbk-scale` |
| `hbk-blur` | Blur and opacity | `--hbk-blur` |

Only the two slides animate height. The others leave the neighbours
jumping into the space, the way the same effects do in Svelte without
`animate:flip`.

The file declares each class with Tailwind's `@utility`, not as a plain
class. That places the rules in the utilities layer, above daisyUI's
components (a plain `.hbk-slide` would lose its `display` to `.card`),
and it lets a single utility on the element override one property,
because Tailwind orders utilities that set several properties before
those that set one:

```erb
<div id="note_<%= note.id %>" data-motion class="hbk-fade duration-500">
<div id="toast" data-motion class="hbk-fly [--hbk-fly-y:2rem]">
```

Two consequences of `@utility` are worth knowing. Tailwind emits a
utility only where it sees the name in your content, so rebuild the
stylesheet after adding a class name to a view, as the post-install
notice says. And the `in-*` variant the slides use needs Tailwind 4.1 or
later.

## Without Tailwind

`--css=none` writes no motion at all, on the reasoning that an app
styling by hand will wire it the same way. The contract is small enough
to write directly:

```css
.note                       { transition: opacity 300ms, translate 300ms }
.note[data-motion-leaving]  { opacity: 0; translate: 0 1rem }
@starting-style {
  .note                     { opacity: 0; translate: 0 1rem }
}
```

Mark the element `data-motion`, give it an id, and the module does the
rest.

## Limits

- Only stream renders and transmit swaps hold. A page morph from Turbo
  Drive replaces the page without asking, and marked elements it removes
  pop.
- The module waits for the marked element's own animations. An infinite
  animation on the element itself, such as a pulsing background, makes
  every removal wait out the ceiling. Put spinners and pulses on
  children.
- `own` reads the trip records of a generic island, the one the
  `hibiki` Stimulus controller drives. A `ChannelController` subclass
  keeps its own records, so its `own` marks behave as plain ones unless
  it calls `trackControl` for its gestures.
- The scaffold's `--skip-motion` leaves every trace out: no stylesheet,
  no import, no marks. See
  [CRUD notes]({{ "/crud-notes/" | relative_url }}#motion) for what the
  generated views carry.
