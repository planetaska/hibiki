---
title: Threading model
nav_order: 1
---

# Threading model

Hibiki's bookkeeping is isolated per execution context, and the context is
the **fiber** (each thread gets that automatically via its root fiber):

- The tracking window (which derived/effect is currently computing) and
  effect ownership live in [fiber storage](https://docs.ruby-lang.org/en/master/Fiber.html#method-c-5B-5D)
  (`Fiber[]`), which child fibers inherit — so reads made through an
  `Enumerator`'s internal fiber still register their dependencies.
- Batch state is fiber-local but *not* inherited: a batch belongs to the
  fiber that opened it, and only that fiber's writes are coalesced.

Independent signal graphs on different threads, fibers, or Ractors never
interfere. A Ractor can run its own reactive world (signals are unshareable
objects, so a graph can't cross a Ractor boundary anyway).

What Hibiki does **not** do is synchronize the graph itself: a signal graph
is confined to the execution context that uses it, and sharing one graph
between concurrently running threads is not supported — same single-threaded
worldview as Solid and Svelte.
