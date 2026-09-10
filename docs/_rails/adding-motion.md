---
title: Adding motion
nav_order: 7
---

# Adding motion

The index page the scaffold generates moves in three places. The create
form slides open when you click New and slides shut when you cancel or
save. The inline edit form does the same. And a row you destroy slides
out to the left before the rows below close the gap. This page starts
smaller than that, with one class on one element, and builds up to what
the scaffold wrote, so that you can change it or add motion of your own.
It stays practical throughout, and
[Motion explained]({{ "/motion-explained/" | relative_url }}) covers the mechanism
behind it for when you would like the full picture.

## Start with an entrance

The list shows a message when no book matches the search. It is in
`_list.html.erb`:

```erb
<p id="books_empty" class="opacity-60 italic">No books match.</p>
```

Add one class:

```erb
<p id="books_empty" class="hbk-fade opacity-60 italic">No books match.</p>
```

If `bin/dev` is running, its CSS watcher rebuilds the stylesheet when
you save. If not, run your app's CSS build, because Tailwind writes out
a class only after it has seen the name in a view. Then search for
something no book matches. The message fades in instead of appearing at
once.

That is all an entrance takes. `hbk-fade` is defined in
`app/assets/stylesheets/hibiki_motion.css`, which the scaffold wrote. It
gives the element a starting look, fully transparent, for the instant
the browser inserts it, and a transition from there to its normal look.
The browser does the rest. There is no attribute to add and no
JavaScript involved, and any element the list re-renders can enter this
way.

## Leaving is the hard part

Now clear the search. The message vanishes at once, with no fade.

The reason is where the page comes from. Everything on it is rendered
on the server. When the search changes, the server re-renders the list
and sends the new HTML, and the browser swaps it in. The old message is
gone the instant the new HTML lands. A transition needs time to run,
and the element is removed before it can start.

The fix is to hold the new HTML back until the leaving element has
finished its transition, and only then swap. That is what the
`hibiki-rails/motion` module does. The scaffold already imported it, as
the line `import "hibiki-rails/motion"` in `app/javascript/application.js`.
To ask for the hold, add `data-motion` to the element:

```erb
<p id="books_empty" data-motion class="hbk-fade opacity-60 italic">No books match.</p>
```

Clear the search again. The message fades out, and the rows take its
place once it has gone. The `id` matters here: the module tells a
leaving element from a staying one by its id. The message already had
one, and an element of your own needs one too.

So a motion that runs both ways is three things on one element: an
`id`, `data-motion`, and an `hbk-` class.

## How the scaffold uses it

Every moving element in the generated views carries those same three
things. Here is the create form's card from `_list.html.erb`:

```erb
<div id="book_new" data-motion class="hbk-slide card bg-base-100 shadow-sm">
  <div class="hbk-slide-body card-body">
    ...
  </div>
</div>
```

The slide differs from the fade in one way: it is a pair of classes,
`hbk-slide` on the box and `hbk-slide-body` on its child, because a
height animation needs both. The row in `_book.html.erb` uses the
sideways pair, `hbk-slide-x` and `hbk-slide-x-body`, and carries
`data-motion="own"` instead of a plain `data-motion`. The difference is
explained [below](#animate-only-what-the-user-removed).

## The six effects

`hibiki_motion.css` defines six effects. Each is a class name you put on
the element, and the file holds the timing.

| Class | What it does | Runs on |
| --- | --- | --- |
| `hbk-slide` and `hbk-slide-body` | Slides open by height, and shut again. Padding and list spacing collapse with it | enter and leave |
| `hbk-slide-x` and `hbk-slide-x-body` | Slides left and fades, then closes the gap. The shape of a swipe-to-delete | leave only |
| `hbk-fade` | Fades in and out | enter and leave |
| `hbk-fly` | Fades while moving from an offset, 1rem below by default | enter and leave |
| `hbk-scale` | Fades while growing from 95 per cent | enter and leave |
| `hbk-blur` | Fades while sharpening from a blur | enter and leave |

The two slides are pairs: one class on the element that has the id, and
the body class on its only child. The other four are single classes on
the element itself.

Only the slides animate height. With any other effect the neighbours
jump into the space the moment the element goes, which is fine for a
message and jarring for a row in a list.

## Change the timing

The timing lives in one place. Open `hibiki_motion.css` and find the
effect:

```css
@utility hbk-fade {
  @apply transition-opacity duration-300
    starting:opacity-0 data-motion-leaving:opacity-0
    motion-reduce:transition-none;
}
```

Change `duration-300` to `duration-500` and every fade on the page
takes half a second. The easing utilities work the same way:
`ease-out`, `ease-in`, and `ease-in-out` are all Tailwind classes.

To change one element without touching the file, put the utility
beside the effect's class name. A utility on the element wins over the
same property inside the effect:

```erb
<div id="book_new" data-motion class="hbk-slide duration-500 ease-in-out card ...">
```

Three effects take a parameter, set as a custom property in square
brackets, Tailwind style:

```erb
<div id="flash" data-motion class="hbk-fly [--hbk-fly-y:-1rem]">
<div id="flash" data-motion class="hbk-fly [--hbk-fly-x:2rem] [--hbk-fly-y:0px]">
<div id="flash" data-motion class="hbk-scale [--hbk-scale:0.8]">
<div id="flash" data-motion class="hbk-blur [--hbk-blur:8px]">
```

`--hbk-fly-x` and `--hbk-fly-y` set where the element flies from and to.
`--hbk-scale` sets the starting size. `--hbk-blur` sets the starting
blur.

## Swap one effect for another

Swapping is a change of class name, with the pairs as the one thing to
watch. Here is the create form fading instead of sliding:

```erb
<div id="book_new" data-motion class="hbk-fade card bg-base-100 shadow-sm">
  <div class="card-body">
```

The outer class changed from `hbk-slide` to `hbk-fade`, and the inner
element lost `hbk-slide-body` because a fade has no body class. Going
the other way, from a single class to a slide, adds the body class to
the child. The row works the same: `hbk-slide-x` on the row and
`hbk-slide-x-body` on the card inside become one class on the row.

A class that is new to your views needs a CSS rebuild before it does
anything, as in the [first example](#start-with-an-entrance).

## Marking markup of your own

The message was an existing element with an id, inside the list. New
markup needs the same, and three more things hold:

- **It must sit inside the part of the page the channel re-renders.** A
  motion runs when a re-render adds or removes the element. Inside the
  list everything qualifies. A heading outside the island never
  re-renders, so it never moves.
- **Mark the outermost element.** A marked element inside another
  marked element moves with its parent.
- **An element that replaces another in the same spot needs an id of
  its own**, and the one it replaces needs a different id. The row's
  edit form and its display markup are the scaffold's example. The
  reference explains why under
  [How an enter works]({{ "/motion-explained/" | relative_url }}#how-an-enter-works).

## Animate only what the user removed

A row can leave the list because the user destroyed it, but also
because they searched for something else, sorted, changed page, or
because someone else destroyed it in another tab. Sliding is right for
the first case only. Twenty rows sliding shut one after another on a
search is a slow page, not a nice one.

`data-motion="own"` tells the row to animate its leave only when the
click that removed it came from inside the row: its own Destroy
button, or its own inline form. Every other removal is instant. The
scaffold marks rows this way and marks the forms with a plain
`data-motion`, because a form only ever leaves when the user closes it.
Use `own` on anything that lives in a list, and plain `data-motion` on
anything that leaves only when the user asks it to.

## Turn it off

- **For a whole resource, at generation time.** Pass `--skip-motion` to
  the scaffold, and it writes no marks, no stylesheet, and no import.
  The `--css=none` variant never writes motion at all, since the effects
  are Tailwind utilities.
- **For one element.** Remove `data-motion` and the `hbk-` classes from
  it. Nothing else references them.
- **For visitors who prefer reduced motion.** Every effect ends with
  `motion-reduce:transition-none`, so a visitor whose system setting asks
  for reduced motion sees no animation at all. Keep that line in any
  effect you add to the file.

The entrance half of each effect relies on `@starting-style`, which
every current browser supports. An older browser shows the element in
place with no entrance and still plays the leave.

## Using your own animations

`hibiki_rails` ships these effects to save you work: a generated page
animates without any animation code of your own. You can replace them.
`hibiki_motion.css` is an ordinary stylesheet in your app, so you can
rewrite any effect in your own CSS, under the same class name or a
different one, and the module still holds each leaving element until its
animation ends. You can also use an animation library, or the browser's
View Transitions API, instead of the module. The JS client fires an
event before each swap, and your code can run the swap inside an
animation of its own.
[Motion explained]({{ "/motion-explained/" | relative_url }}#bringing-your-own-animation)
describes both options.

## Where to read next

- [Motion explained]({{ "/motion-explained/" | relative_url }}) covers the mechanism: the
  attributes, how a leave is held, and how an enter works.
- The motion section of
  [CRUD notes]({{ "/crud-notes/" | relative_url }}#motion) lists what the
  generated views carry and why the row is shaped as it is.
