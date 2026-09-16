# Adding motion (digest)

Practical side: put an effect on an element, tune it, swap it, choose `own`
or plain, turn it off. The mechanism is in `motion-explained.md`.

## Entrance, then leave

```erb
<p id="books_empty" class="hbk-fade opacity-60 italic">No books match.</p>
```

One class gives an entrance: `@starting-style` sets the opening look for the
instant of insertion and the transition runs from there, no attribute or JS.
Rebuild the CSS after a class name new to your views (`bin/dev` does it on
save), because Tailwind writes a class only after seeing the name.

The leave needs the hold, because the swap removes the old element the instant
the new HTML lands. Import `hibiki-rails/motion` once in
`app/javascript/application.js` (the scaffold did) and add `data-motion`:

```erb
<p id="books_empty" data-motion class="hbk-fade opacity-60 italic">No books match.</p>
```

The `id` is required: the module tells leaving from staying by id. A motion
both ways is three things on one element: `id`, `data-motion`, `hbk-` class.

## What the scaffold writes

| Element | Mark | Classes |
|---|---|---|
| `#book_new` create card | `data-motion` | `hbk-slide` on the card, `hbk-slide-body` on `card-body` |
| `#book_7_edit` edit wrapper | `data-motion` | the `hbk-slide` pair |
| `#book_7` row | `data-motion="own"` | `hbk-slide-x` on the row, `hbk-slide-x-body card card-body` on its one child |

Display markup sits in `<div id="book_7_display" class="contents">` so the
edit form swaps for an element with a different id instead of being morphed
into it; the row's card and body are one element so the add-on generators
find field lines at the indentation they expect.

## The six effects

| Class | Does | Runs on |
|---|---|---|
| `hbk-slide` + `hbk-slide-body` | Height slide; padding and `space-y-*` gap collapse too | enter and leave |
| `hbk-slide-x` + `hbk-slide-x-body` | Slides left and fades, then closes the gap | leave only |
| `hbk-fade` | Fades | enter and leave |
| `hbk-fly` | Fades while moving from an offset (1rem below by default) | enter and leave |
| `hbk-scale` | Fades while growing from 95% | enter and leave |
| `hbk-blur` | Fades while sharpening from a blur | enter and leave |

Pairs: outer class on the element with the id, body class on its only child.
Only the slides animate height; with the others the neighbours jump.

## Tuning, parameters, swapping

- Page-wide: edit the effect in `app/assets/stylesheets/hibiki_motion.css`
  (`duration-300` to `duration-500`; `ease-out`, `ease-in`, `ease-in-out`).
- One element: a utility beside the class name wins,
  `class="hbk-slide duration-500 ease-in-out ..."`.
- Parameters as custom properties on the element: `hbk-fly [--hbk-fly-y:-1rem]`,
  `hbk-fly [--hbk-fly-x:2rem] [--hbk-fly-y:0px]`, `hbk-scale [--hbk-scale:0.8]`,
  `hbk-blur [--hbk-blur:8px]`.
- Swap by changing the class name and watching the pairs: `hbk-slide` to
  `hbk-fade` on the card also drops `hbk-slide-body` from the child; single
  to slide adds it. Any new name needs a CSS rebuild.

## Marking your own markup

- It must sit inside the region the channel re-renders; a heading outside the
  island never re-renders, so it never moves.
- Mark the outermost element; an inner mark moves with its parent.
- An element replacing another in the same spot needs its own id, and the one
  it replaces a different id (morph pairs by id, and a rewritten element never
  plays its entrance).

## `own` versus plain

`data-motion="own"` animates the leave only when the click came from inside
the element (its own Destroy button or inline form); use it on anything in a
list, since a search that slides twenty rows shut is a slow page. Plain
`data-motion` always animates; use it on anything that leaves only on
request, such as a form.

## Turning it off

- Resource: `--skip-motion` on the scaffold (no marks, stylesheet or import).
  `--css=none` never writes motion; the output is the same.
- Element: remove `data-motion` and the `hbk-` classes.
- Reduced motion: every effect ends in `motion-reduce:transition-none`; keep
  it in effects you add.

Own animations: rewrite any effect under its class name in any stylesheet, or
use View Transitions or a library on the pre-swap events (`motion-explained.md`).

See also: https://planetaska.github.io/hibiki/crud-notes/
Full docs: https://planetaska.github.io/hibiki/adding-motion/
