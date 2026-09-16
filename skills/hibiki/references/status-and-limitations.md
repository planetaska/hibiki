# Status and limitations (hibiki 0.3.0)

## Guaranteed

| Guarantee | In one line |
|---|---|
| Runtime dependency tracking | reads register dependencies, writes notify subscribers, nothing else does |
| Dynamic dependencies | re-collected on every run; `flag ? a : b` follows the branch it took last |
| Lazy deriveds | recompute on a read while stale, never at the write |
| Equal writes are no-ops | `==` by default; `equals:` replaces the comparison per signal, `false` disables it |
| Batching and glitch freedom | `batch { }` runs each affected effect once at the end; every write is a batch of one, so a diamond never runs an effect against a half-updated graph |
| The equality gate | at the flush an effect re-runs only if a value it read changed by that signal's equality; `Effect#run` bypasses it |
| Ownership | effects and cleanups belong to the running effect or root; `Hibiki.root` anchors long-lived graphs |
| Disposal is final | a disposed effect never runs again, not from a write, a pending batch, or a late scheduler |
| Error isolation | one raising effect never stops a flush; the first error re-raises afterwards unless `Hibiki.error_handler` takes it |
| Scheduled re-runs | `effect(scheduler:)` hands re-runs to your callable |
| Untracked reads | `peek` for one signal, `Hibiki.untrack { }` for a block |
| Isolation per flow | each thread, fiber and Ractor keeps its own bookkeeping |
| Class-based reactivity | `Hibiki::Reactive` macros |
| Plain Ruby | Ruby >= 3.4, no runtime dependencies, opt-in DSL |

## Left to you

- One thread per graph: signals hold no locks; other threads send messages.
- In-place changes: `<<`, `merge!` and kin never write a signal.
- No cycle detection: an effect writing what it reads, or two effects feeding each other, re-run until `SystemStackError`. Read what you write through `peek`.
- No disposal for deriveds: no `dispose`, no owner; once read, a derived stays subscribed to its sources as long as they live. Create it once beside the states it reads, not per run or per request.
- No ownership inside a derived: an effect or cleanup created in a derived block belongs to whichever effect read it. Keep derived blocks side-effect free.
- No gate on deriveds: an equal recompute still marks downstream deriveds stale; only effects are gated.
- Errors outside a batch: a raise on an effect's first run leaves `Effect.new`; a raise in a scheduler-deferred `run` reaches whoever called `run`.
- One error handler per Ractor; none per effect or root.
- No deferred runs: an effect re-runs on the writer's stack, inside the write. No async primitive; wait outside the graph and write the result into a state.
- No signals across Ractors.
- No introspection of a `Reactive` instance (parked until someone needs rehydration).

Full docs: https://planetaska.github.io/hibiki/status-and-limitations/
