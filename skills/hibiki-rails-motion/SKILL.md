---
name: hibiki-rails-motion
description: >-
  Enter and leave transitions for hibiki_rails re-renders (hibiki_rails 0.15.0): the `hibiki-rails/motion` module, `data-motion` and `data-motion="own"` you write, `data-motion-leaving` and `data-motion-entering` the module sets, the six utilities in `hibiki_motion.css` (`hbk-slide` + `hbk-slide-body`, `hbk-slide-x` + `hbk-slide-x-body`, `hbk-fade`, `hbk-fly`, `hbk-scale`, `hbk-blur`) with their `--hbk-*` parameters, duration/easing overrides, `@starting-style`, `motion-reduce`, plain CSS without Tailwind, the `hibiki:before-render` and `turbo:before-stream-render` seams for View Transitions or GSAP, id rules under morph, the one-second ceiling, `--skip-motion`. Load whenever a row, card, form, flash or toast on a hibiki_rails page should slide, fade, fly, scale or blur, an element "vanishes before its animation", "only animate my own destroy", or you are editing hibiki_motion.css. Load hibiki-rails for channels, islands and the JS client; hibiki-rails-scaffold for the generator that writes the marks.
license: MIT
metadata:
  author: planetaska
  hibiki: "0.3.0"
  hibiki_rails: "0.15.0"
  hibiki_phlex: "0.1.0"
---

# hibiki-rails-motion

Enter and leave transitions for pages that hibiki_rails re-renders from the
server. This skill covers hibiki_rails 0.15.0 (npm `hibiki-rails` 0.15.0 in
lockstep); the family versions table lives in the `hibiki` skill.

## The problem in three lines

A hibiki_rails page never changes itself: every change arrives as re-rendered
HTML that the JS client swaps in place of the old. An element that enters can
animate with CSS alone, because `@starting-style` gives it an opening look on
insertion. An element that leaves cannot, because the swap removes it before
any transition could start, so something has to hold the new HTML back until
the old element has finished. The `hibiki-rails/motion` module is that hold.

## Three things per element

Import the module once per app, then put three things on every element that
should animate both ways:

```js
// app/javascript/application.js
import "hibiki-rails/motion"
```

```erb
<p id="books_empty" data-motion class="hbk-fade opacity-60 italic">No books match.</p>
```

- Import once, because the module registers document-level listeners at
  import time. The scaffold appends the line for you (`scaffold_motion.rb`)
  and prints a yellow `motion` notice when `app/javascript/application.js`
  is missing, since without the import rows pop instead of sliding.
  Importmap apps resolve it through the engine's `pin "hibiki-rails/motion"`;
  bundler apps through the npm package's `./motion` export.
- Give the element an `id`, because the module tells a leaving element from a
  staying one by comparing ids with the incoming HTML, the same rule the
  client uses to decide which fragment a swap replaces.
- Add `data-motion`, because only marked elements are considered; an unmarked
  page costs two `querySelector` calls per render and nothing else.
- Add a class (`hbk-*` or your own) that describes the motion, because the
  module sets attributes and waits; it draws nothing itself.

An entrance alone needs only the class: `@starting-style` runs on a real
insertion with no help from the module.

## The attribute contract

| Written by | Attribute | Meaning |
|---|---|---|
| you | `data-motion` | Animate the leave; mark the element while it enters |
| you | `data-motion="own"` | Animate the leave only when a gesture inside this element removed it |
| the module | `data-motion-leaving` | Present from the moment a render would remove the element until its transitions end |
| the module | `data-motion-entering` | Present from the moment a render inserted the element until its first transitions end |

Only read the two module-written attributes, because the module owns their
lifetime. All four are public, unlike the private `data-hibiki-*` attributes
the helpers emit. Plain CSS reaches them with attribute selectors; Tailwind
reaches them with variants: `starting:` for the entrance (Tailwind's spelling
of `@starting-style`), `data-motion-leaving:` on the element itself, and
`in-data-motion-leaving:` on a descendant of a leaving element (Tailwind
4.1 or later).

## The six effects

`app/assets/stylesheets/hibiki_motion.css`, written once per app by the
scaffold under `--css=daisyui` or `--css=tailwind`, defines each effect as a
Tailwind `@utility`:

| Class | Effect | Runs on | Parameters (default) |
|---|---|---|---|
| `hbk-slide` on the box, `hbk-slide-body` on its only child | Slides open and shut by height; the child's padding and a `space-y-*` margin collapse with it | enter and leave | none |
| `hbk-slide-x` on the wrapper, `hbk-slide-x-body` on the card inside | The card slides left and fades, then the wrapper closes the gap (swipe-to-delete) | leave only | none |
| `hbk-fade` | Opacity | enter and leave | none |
| `hbk-fly` | Position and opacity, from an offset | enter and leave | `--hbk-fly-x` (0px), `--hbk-fly-y` (1rem) |
| `hbk-scale` | Size and opacity | enter and leave | `--hbk-scale` (0.95) |
| `hbk-blur` | Blur and opacity | enter and leave | `--hbk-blur` (4px) |

The slides are pairs because a transition cannot run to a height the browser
computes: the outer element is a grid whose single row grows from `0fr` to
`1fr`, and the inner element collapses its padding alongside. The sideways
slide is a pair for a second reason too: one element cannot both slide away
and be the box whose height closes the gap. Only the slides animate height;
the other four leave the neighbours jumping into the gap, which is fine for a
message and jarring for a row in a list.

## Tuning

Change every instance of an effect in the file, since the views carry only
class names and the timing lives in one place:

```css
@utility hbk-fade {
  @apply transition-opacity duration-300
    starting:opacity-0 data-motion-leaving:opacity-0
    motion-reduce:transition-none;
}
```

Change `duration-300` to `duration-500`, or `ease-out` to `ease-in-out`, and
the next CSS build applies it page-wide.

Change one element by putting the utility beside the class name. It wins
because `@utility` places the rules in Tailwind's utilities layer and Tailwind
orders a multi-property utility before a single-property one:

```erb
<div id="book_new" data-motion class="hbk-slide duration-500 ease-in-out card">
<div id="flash" data-motion class="hbk-fly [--hbk-fly-y:-1rem]">
<div id="flash" data-motion class="hbk-fly [--hbk-fly-x:2rem] [--hbk-fly-y:0px]">
<div id="flash" data-motion class="hbk-scale [--hbk-scale:0.8]">
<div id="flash" data-motion class="hbk-blur [--hbk-blur:8px]">
```

Rebuild the stylesheet after adding a class name new to your views, because
Tailwind emits a utility only where it has seen the name in content; `bin/dev`
does it on save.

## Swapping effects

Swap by changing the class name, and watch the pairs. The create form fading
instead of sliding:

```erb
<div id="book_new" data-motion class="hbk-fade card bg-base-100 shadow-sm">
  <div class="card-body">
```

The outer class changed and the child lost `hbk-slide-body`, since a fade has
no body class. Going from a single class to a slide adds the body class to the
child. The row works the same way: `hbk-slide-x` on the row plus
`hbk-slide-x-body` on the card become one class on the row.

## `own` versus plain

Use `data-motion="own"` on anything that lives in a list, because a row
leaves for many reasons (destroyed, filtered out, paged past, destroyed in
another tab) and only the user's own destroy deserves a slide; twenty rows
sliding shut on a search is a slower page, not a nicer one. Use plain
`data-motion` on anything that leaves only when the user asks it to, such as
a create or edit form. The scaffold marks rows `own` and forms plain.

`own` is judged from the island's gesture records: the control of an
in-flight trip, or the last control the island tracked (`island.busy` and
`island.lastControl` in the client). No attribute on the control is needed,
and a fast destroy still counts even when it settled before the busy
indicator would have shown.

## How the hold works

The module listens for both pre-swap events, because HTML reaches the page by
two routes: Turbo's `turbo:before-stream-render` for broadcasts and
`hibiki:before-render` for the transmit transport. On each it replaces
`event.detail.render` with a held version, which when its turn comes:

1. Collects marked elements under the target whose id the incoming content
   lacks; for `own` marks, only those that own the gesture.
2. Keeps only the outermost, since a marked element inside a leaving one
   leaves with its parent.
3. Sets `data-motion-leaving` on each, waits one `requestAnimationFrame`
   (transitions exist only after the next style pass), then waits for the
   element's own `getAnimations()` to finish.
4. Runs the render, clears `data-motion-leaving` from any element the render
   kept after all, and clears the island's `lastControl` so the gesture is
   consumed.
5. Sets `data-motion-entering` on marked elements new to the document and
   removes it when their first animations end.

Rules the hold keeps:

- Renders queue in arrival order, one chain per document, so a held render
  never lets a later one overtake it; a failed render does not close the
  chain.
- Every wait races a one-second ceiling (`CEILING = 1000` in
  `hibiki-motion.js`), so a transition that never ends cannot stall the page.
- A hidden tab waits for nothing, because browsers run no transitions there.
- Only stream actions that remove content are held: `replace`, `update` and
  `remove`. `append`, `prepend`, `before`, `after` and `refresh` run at once.
- Under `replace` and `remove` the target itself is a candidate; under
  `update` only its descendants are. Over transmit only descendants can leave,
  since a root id always survives a by-id swap.

## Enter under morph needs a different id

The scaffold's list updates by morph: Turbo pairs each old element with its
counterpart, by id first and by tag name when there is none, and rewrites
each pair in place. A rewritten element was never inserted, so
`@starting-style` never fires for it. Give the element that should animate in
an id of its own, and give the element it replaces a different id, so Turbo
swaps one for the other instead of morphing one into the other. The scaffold
keeps `<div id="book_7_display" class="contents">` beside
`<div id="book_7_edit">` for exactly this reason; a bare `<div>` in either
place would be paired with the other and would never animate.

## Without Tailwind, or bringing your own

`--css=none` writes no motion, on the reasoning that an app styling by hand
wires it the same way it wires everything else. The contract in plain CSS is
three rules:

```css
.note                      { transition: opacity 300ms, translate 300ms }
.note[data-motion-leaving] { opacity: 0; translate: 0 1rem }
@starting-style {
  .note                    { opacity: 0; translate: 0 1rem }
}
```

Keep the module and write your own CSS when you want the hold without the
utilities: the module does not read `hibiki_motion.css`, it only sets the
attributes and waits on `getAnimations()`, which covers transitions,
keyframes and the Web Animations API. The queue, the ceiling and the
outermost rule still apply.

Leave the module out and hold the swap yourself when you want View
Transitions or a library: both events carry the swap in `event.detail.render`,
and a replacement that returns a promise is awaited. `hibiki:before-render`
bubbles from the island with `detail { island, content, render }`; Turbo's
`render` takes the stream element, so pass it through:

```js
document.addEventListener("hibiki:before-render", (event) => {
  const render = event.detail.render
  event.detail.render = () => document.startViewTransition(render).finished
})
document.addEventListener("turbo:before-stream-render", (event) => {
  const render = event.detail.render
  event.detail.render = (streamElement) =>
    document.startViewTransition(() => render(streamElement)).finished
})
```

GSAP or any promise-returning library fits the same seam: diff the ids in
`content` against the page to find the leaving elements, await the tween,
then call `render()`. The snippet is in `references/motion-explained.md`.

## Turning it off

- For a whole resource at generation time, pass `--skip-motion`: no marks,
  no stylesheet, no import. `--css=none` never writes motion either, because
  the effects are Tailwind utilities (`motion? = css? && !options[:skip_motion]`
  in the generator), so the two produce identical views.
- For one element, remove `data-motion` and the `hbk-` classes; nothing else
  references them.
- For visitors who prefer reduced motion, nothing to do: every effect ends in
  `motion-reduce:transition-none`. Keep that line in any effect you add.

Without the import a marked element still works, just at once. A browser
without `@starting-style` shows the element in place and still plays the
leave.

## Pitfalls

- A leave needs all three: the import, `data-motion`, and an `id`. The module
  only registers on import, only considers marked elements, and keys leaving
  by id, so an element missing any one appears and disappears at once.
  (adding-motion)
- The element sits outside the part of the page the channel re-renders. A
  motion runs when a re-render adds or removes the element, so a heading
  outside the island never moves. (adding-motion)
- Mark the outermost element. A marked element inside a leaving one leaves
  with its parent, in both phases. (motion-explained)
- Same id on the element that replaces another under morph. Turbo rewrites
  paired elements in place and a rewritten element never fires
  `@starting-style`; give the pair different ids. (motion-explained)
- A slide without its body class, or a body class left behind after a swap.
  The slides are pairs because the height animation needs a grid box and a
  padding-collapsing child; the other four are single classes. (adding-motion)
- A new `hbk-*` class does nothing. Tailwind emits a utility only where it has
  seen the name in a view, so rebuild the CSS; and the `in-*` variant the
  slides use needs Tailwind 4.1 or later. (motion-explained)
- `own` on a page driven by a `ChannelController` subclass over Turbo
  broadcasts never animates. `own` needs an island's gesture records, and
  `islandFor` walks only generic islands, so the module finds no island and
  treats no evidence as "not own"; plain `data-motion` still animates. Over
  transmit a subclass's `own` marks work once it calls `trackControl` for its
  gestures. (motion-explained)
- A pulsing or spinning animation on the marked element itself. The module
  waits for the element's own animations (`getAnimations()` without subtree),
  so an animation that never ends makes every removal wait out the one-second
  ceiling; put spinners on children. (motion-explained)
- Expecting a hold on `append`, `prepend`, or a Turbo Drive page morph. Only
  `replace`, `update` and `remove` remove content, and a Drive refresh
  replaces the page without firing the stream event. (motion-explained)
- Dropping `motion-reduce:transition-none` from an effect you edit. It is
  what a visitor's reduced-motion setting relies on. (adding-motion)
- Writing `data-motion-leaving` or `data-motion-entering` yourself. The
  module sets and clears them around each swap, so a hand-set one is removed
  or stuck. (motion-explained)
- Putting a duration or parameter override on a parent instead of on the
  element. Overrides win because they sit beside the effect's class name on
  the same element in the utilities layer. (adding-motion)
- Expecting `--skip-motion` and `--css=none` to differ. Both write views with
  no marks, no stylesheet and no import. (crud-notes)

## Reference files

- `references/adding-motion.md`: open when adding or changing an effect on an
  element, tuning a duration, swapping slide for fade, or deciding between
  `own` and plain.
- `references/motion-explained.md`: open for the attribute contract, the hold
  algorithm and its rules, the morph id rule, plain-CSS and bring-your-own
  seams (View Transitions, GSAP), and the limits.

## Related skills

- `hibiki`: the signal core and the family router with the versions table.
- `hibiki-rails`: channels, islands, `on`, the JS client and the two render
  routes the hold sits on.
- `hibiki-rails-scaffold`: the generator that writes the marks, the
  stylesheet and the import, and its `--skip-motion` and `--css` options.
- `hibiki-rails-forms`: reactive forms behind the inline create and edit
  cards that slide.
- `hibiki-phlex`: reactive Phlex components; their transmit swaps fire the
  same `hibiki:before-render` event.
