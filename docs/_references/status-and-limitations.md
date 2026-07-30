---
title: Status & limitations
nav_order: 6
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
- **Equality gate** — an effect re-runs only when at least one of the values
  it read actually changed (`==`). Svelte's `$derived` compares; Hibiki
  compares on the reading side, at the flush, against what the effect last
  read — so a write that ripples through a derived to the same value costs a
  recompute and nothing else. Two consequences worth knowing:
  - a derived that returns the same object it mutated compares equal to
    itself, so the gate swallows the update (Svelte documents the same
    caveat). Return a new object — see
    [mutable defaults](mutable-defaults.md);
  - an effect that must fire on every write rather than on every *change* — a
    heartbeat, a log line, a counter — should read the value that genuinely
    changes (`effect { version.value; log(...) }`) rather than a derived
    summary that often doesn't. `Effect#run` bypasses the gate, so a
    scheduler that decides to run always runs.
- **Error isolation** — a raising effect doesn't take the rest of a flush
  down with it: the queue always completes, then the first error re-raises.
  Set `Hibiki.error_handler = ->(error, effect) { ... }` (Solid's
  `handleError`) to route errors instead — e.g. to `Rails.error.report` —
  so one broken effect never raises out of a write.
- **Effect disposal** — `Effect#dispose`, with ownership: effects created
  inside an effect are disposed when their owner re-runs or is disposed.
- **Scheduler seam** — `Effect.new(scheduler: ->(effect) { ... })` (Vue's
  `ReactiveEffect` scheduler) hands re-runs to your callable instead of
  running them inline; call `effect.run` when ready — on the graph's own
  execution context. Lets an integration debounce or coalesce chosen
  effects (e.g. one broadcast per burst of writes) while other effects
  stay synchronous. The initial run is never scheduled, and a run after
  `dispose` is a no-op.
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
