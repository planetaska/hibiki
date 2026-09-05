---
title: Status & limitations
nav_order: 5
---

# Status & limitations

Hibiki 0.3.0 is a small signal core: three primitives, batching, and ownership. This page lists what the core guarantees, what it leaves to you, and what has been decided and closed.

## Already in place

- **Runtime dependency tracking.** Reads register dependencies and writes notify subscribers. See [the three primitives]({% link _guides/getting-started.md %}#the-three-primitives).
- **Dynamic dependencies.** Dependencies are collected afresh on every run, so an effect that reads `flag ? a : b` follows the branch it took last and drops the other.
- **Lazy deriveds.** A derived recomputes when it is read and stale, never when a source is written.
- **Equal writes are no-ops.** A write that compares equal to the held value notifies nobody. `equals:` replaces the comparison per signal, or disables it with `false`. See [custom equality]({% link _guides/advanced-usage.md %}#custom-equality-equals).
- **Batching.** `batch { }` applies writes at once and runs each affected effect once at the end. See [batching]({% link _guides/advanced-usage.md %}#batching-several-writes-in-one-run).
- **Glitch freedom.** Every write is a batch of one, so a diamond-shaped graph never runs an effect against a half-updated graph.
- **The equality gate.** At the end of a batch, an effect re-runs only if a value it read has changed by that signal's equality. `Effect#run` bypasses the gate. See [when an effect re-runs]({% link _references/lifecycle-in-detail.md %}#when-an-effect-re-runs).
- **Ownership.** Effects and cleanups created while an effect or root runs belong to it, and come down with it on re-run or dispose. `Hibiki.root` anchors a graph whose teardown is an external event. See [the owner tree]({% link _references/lifecycle-in-detail.md %}#the-owner-tree).
- **Disposal is final.** A disposed effect never runs again, not from a write, a pending batch, or a late scheduler. See [disposal]({% link _references/lifecycle-in-detail.md %}#disposal-is-final).
- **Error isolation.** One raising effect never stops a batch from finishing. The first error re-raises afterwards, unless `Hibiki.error_handler` takes it. See [errors in effects]({% link _ref_rails/error-handling-layers.md %}#layer-2-hibikierror_handler-for-errors-in-effects).
- **Scheduled re-runs.** `effect(scheduler: ...)` hands re-runs to your callable, so an integration can debounce or coalesce chosen effects. See [scheduled re-runs]({% link _references/lifecycle-in-detail.md %}#scheduled-re-runs).
- **Untracked reads.** `peek` reads one signal without subscribing, and `Hibiki.untrack { }` does the same for a block. See [untracked reads]({% link _guides/advanced-usage.md %}#untracked-reads-reading-without-listening).
- **Isolation per flow of execution.** Each thread, fiber, and Ractor keeps its own tracking bookkeeping. See the [threading model]({% link _references/threading-model.md %}).
- **Class-based reactivity.** `Hibiki::Reactive` declares signals as class macros. See [class-based reactivity]({% link _guides/class-based-reactivity.md %}).
- **Plain Ruby.** Ruby 3.4 or later, no runtime dependencies, opt-in DSL.

## Limitations

- **One thread per graph.** Signals hold no locks. A graph lives on one thread, and other threads send it messages. See [writing from another thread]({% link _references/threading-model.md %}#writing-to-a-graph-from-another-thread).
- **Changes made in place.** `<<`, `merge!`, and their kin change an object without a write, and the graph never hears of it. See [mutable state defaults]({% link _references/mutable-defaults.md %}#changing-a-value-in-place-is-not-a-write).
- **No cycle detection.** An effect that writes a signal it reads, or two effects that feed each other, re-run until Ruby raises `SystemStackError`. Read what you write through `peek`.
- **No disposal for deriveds.** A derived has no `dispose`, and no owner. Once read, it stays subscribed to its sources for as long as they live, and they keep it alive. Create a derived once, next to the states it reads, rather than per run or per request.
- **No ownership inside a derived.** Deriveds are values, not owners. An effect or cleanup created inside a derived block belongs to whichever effect happened to read the derived. Keep derived blocks free of side effects.
- **No gate on deriveds.** The equality gate protects effects only. A derived that recomputes to an equal value still marks the deriveds downstream of it stale, and each recomputes on its next read.
- **Errors outside a batch.** `Hibiki.error_handler` covers re-runs inside a batch. A raise on an effect's first run leaves `Effect.new`, and a raise inside a run the scheduler deferred reaches whoever called `run`.
- **One error handler per Ractor.** It is set once for the whole Ractor. An effect or root cannot carry a handler of its own.
- **No deferred runs.** An effect re-runs inside the write that changed its source, on the writer's stack. Nothing is deferred to a later tick, and there is no primitive for asynchronous data. Do the waiting outside the graph and write the result into a state.
- **No signals across Ractors.** A signal belongs to the Ractor that made it. Each Ractor runs its own reactive world. See [Ractors]({% link _references/threading-model.md %}#ractors-one-world-per-ractor).
- **No introspection of a `Reactive` instance.** There is no way to enumerate, dump, or restore an instance's signals. This is parked until someone needs to rehydrate one.
