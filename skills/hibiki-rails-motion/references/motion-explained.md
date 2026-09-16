# Motion explained (digest)

The contract between the `hibiki-rails/motion` module and your CSS. Every
change reaches the page as re-rendered HTML the client swaps in, so an enter
is pure CSS (`@starting-style`) and a leave needs the module to hold the swap
until the old element's transition ends.

## The minimum

Import `hibiki-rails/motion` once in `app/javascript/application.js`, then:

```erb
<div id="note_<%= note.id %>" data-motion class="note">...</div>
```

```css
.note                      { transition: opacity 300ms, translate 300ms }
.note[data-motion-leaving] { opacity: 0; translate: 0 1rem }
@starting-style {
  .note                    { opacity: 0; translate: 0 1rem }
}
```

Importmap apps get `pin "hibiki-rails/motion"` from the engine; the npm
package exports `./motion`. Without the import a marked element still works,
at once. The id is required: leaving means missing from the incoming HTML.

## The attributes

| By | Attribute | Meaning |
|---|---|---|
| you | `data-motion` | animate the leave; mark while entering |
| you | `data-motion="own"` | animate the leave only if a gesture inside it removed it |
| module | `data-motion-leaving` | set when a render would remove it, until its transitions end |
| module | `data-motion-entering` | set when a render inserted it, until its first transitions end |

Public, unlike `data-hibiki-*`. Tailwind variants: `starting:`,
`data-motion-leaving:` (the element), `in-data-motion-leaving:` (a
descendant; Tailwind 4.1+).

## How a leave works

The module listens on `turbo:before-stream-render` (broadcast) and
`hibiki:before-render` (transmit; detail `{ island, content, render }`) and
replaces `detail.render` with a held one: marked elements the incoming HTML
lacks get `data-motion-leaving`, the module awaits their animations, runs the
swap, then sets `data-motion-entering` on marked newcomers. Rules:

- Renders queue in arrival order, one chain per document; none overtakes.
- Every wait races a one-second ceiling (`CEILING = 1000`).
- A hidden tab waits for nothing.
- Only the outermost marked element of a subtree animates.
- Only `replace`, `update` and `remove` are held; `append`, `prepend`,
  `before`, `after` and `refresh` run at once.
- The wait is on the element's own `getAnimations()`, not its descendants.

## How an enter works

`@starting-style` does it; the module only adds `data-motion-entering` for
rules limited to the motion (the scaffold's `overflow-hidden`). Under morph,
Turbo pairs by id then by tag and rewrites in place, and a rewritten element
never fires `@starting-style`: the entering element and the one it replaces
need different ids (`book_7_display` vs `book_7_edit`).

## `own`

Judged from the island's gesture records (`island.busy` controls and
`island.lastControl`), consumed after the render; no attribute on the
control, and fast destroys still count. No island found means not own.

## The ready-made file

`hibiki_motion.css` declares each effect with `@utility`, so it sits in the
utilities layer above daisyUI components and a single-property utility on
the element (`duration-500`, `[--hbk-fly-y:2rem]`) still wins. Defaults:
`--hbk-fly-x` 0px, `--hbk-fly-y` 1rem, `--hbk-scale` 0.95, `--hbk-blur` 4px,
all `duration-300`. Slides are grid boxes (`grid-rows-[1fr]` to `[0fr]`) with
a padding-collapsing child. Rebuild after adding a name to a view.

## Bringing your own

Keep the module and write any CSS against the attributes: it reads no
stylesheet and awaits `getAnimations()` (transitions, keyframes, WAAPI). Or
hold the swap yourself; a promise returned from `detail.render` is awaited.
View Transitions: `event.detail.render = () => document.startViewTransition(render).finished`
(Turbo's `render` takes the stream element, so pass it through). A library:

```js
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

## Limits

- Turbo Drive page morphs (a refresh) are not held; marked elements vanish.
- A never-ending animation on the marked element itself waits out the
  ceiling every time; put spinners on children.
- `own` under a `ChannelController` subclass over Turbo streams never
  animates (`islandFor` knows only generic islands); plain marks do. Over
  transmit the subclass's `own` works once it calls `trackControl`.
- `--skip-motion` and `--css=none` write no motion at all.

Full docs: https://planetaska.github.io/hibiki/motion-explained/
