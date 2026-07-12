---
title: Status & limitations
nav_order: 3
---

# Status & limitations

Hibiki is a young signal core.

Already in place:

- **Stale subscriptions** — dependency lists are cleared before each rerun
  (mirroring Solid), so conditional reads switch subscriptions cleanly.
- **Batching** — `Hibiki.batch { ... }` coalesces effect runs across
  multiple writes.
- **Glitch freedom** — every write is an implicit batch (Solid's
  `runUpdates`), so diamond-shaped graphs never run effects with
  inconsistent intermediate values.
- **Effect disposal** — `Effect#dispose`, with ownership: effects created
  inside an effect are disposed when their owner re-runs or is disposed.
- **Execution-context isolation** — see the [threading model](threading-model.md).
- **Ergonomics** — `Hibiki::Reactive` class macros, `untrack`/`peek`/`call`
  (transparent access and a block DSL were evaluated and rejected — see
  [Why no transparent signals?](why-no-transparent-signals.md)).
