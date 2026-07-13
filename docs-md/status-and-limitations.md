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
- **Lifecycle scoping** — `Hibiki.root { |root| ... }` (Solid's
  `createRoot`) owns everything created inside it and tears it all down on
  `root.dispose` — the anchor for long-lived graphs whose teardown is an
  external event, not a rerun. `Hibiki.on_cleanup { ... }` (Solid's
  `onCleanup`) registers teardown on the owning effect or root, run before
  each rerun and on dispose.
- **Execution-context isolation** — see the [threading model](threading-model.md).
- **Ergonomics** — `Hibiki::Reactive` class macros, `untrack`/`peek`/`call`
  (transparent access and a block DSL were evaluated and rejected — see
  [Why no transparent signals?](why-no-transparent-signals.md)).
