# Lifecycle in detail

Every effect and every root is an **owner**. Whatever is created while its block runs (a child effect, an `on_cleanup` block) belongs to it and comes down with it. The owners form a tree, and the tree is what keeps a reactive program from leaking.

## The owner tree

- While an effect runs its block it is the current owner; an effect created then is adopted and disposed whenever the owner re-runs or is disposed. Without adoption every re-run would leave one more live copy behind.
- `Hibiki.untrack` hides reads only; the owner stays in place, so effects created inside are adopted as usual.
- The owner slot is separate from the tracking slot. A lazy derived recomputing mid-effect registers its `on_cleanup` calls on the effect, because a derived is a value and owns nothing.

## When an effect re-runs

A write never runs an effect directly. The decision is made when the outermost batch closes, and a plain write is a batch of one:

1. The write lands, or not: an equal value (`==`, or the signal's `equals:`) returns early and notifies nobody.
2. Invalidation spreads: each derived downstream marks itself dirty and passes it on; each effect downstream is queued once, however many paths reached it.
3. At the flush every queued effect compares each value it read on its last run with that value now (a dirty derived recomputes here to answer). Nothing differs, no run.

```ruby
count = state(0)
even  = derived { count.value.even? }
effect { puts "even? #{even.value}" } # prints "even? true"

count.value = 0 # equal write, nobody hears
count.value = 2 # even recomputes, still true, no run
count.value = 3 # prints "even? false"
```

Two consequences: a derived's block has no side effects (the check may recompute it inside whichever effect asked, and anything it created would belong to that effect), and `Effect#run` skips the check entirely.

## Scheduled re-runs: `effect(scheduler: ->(e) { ... })`

| Moment | What happens |
|---|---|
| creation | runs inline, never scheduled, because that run collects the dependencies |
| flush finds a changed source | the scheduler is called once with the effect, however many writes the batch held |
| flush finds nothing changed | the scheduler is not called at all |
| `e.run` | runs the block with no check, tears down and re-collects, no-op once disposed; a raise reaches the caller of `run` |
| the scheduler raises | treated like a raising effect: the flush finishes its queue, then re-raises or hands to `Hibiki.error_handler` |

Call `run` on the thread the graph lives on. hibiki_rails's `Debounce` scheduler is built on this contract.

## What a re-run tears down

1. Owned children are disposed first, so a child's cleanup can still use a resource its owner is about to release.
2. The owner's own cleanups run newest first, like nested `ensure` blocks.
3. On a re-run only, the block runs again and subscribes to exactly what it reads this time; the stale branch of `flag ? a : b` is forgotten.

```ruby
effect do
  tick.value
  on_cleanup { log << "outer, first" }
  effect { on_cleanup { log << "child" } }
  on_cleanup { log << "outer, second" }
end
tick.value = 1
log # => ["child", "outer, second", "outer, first"]
```

## `on_cleanup`, roots, disposal

- `on_cleanup { }` registers on the innermost running effect or root; it runs before the next re-run and on dispose. Outside any owner Hibiki warns `Hibiki.on_cleanup: no current owner (effect or root); the cleanup can never run` and drops the block.
- `Hibiki.root { |root| }` escapes the tree: never adopted, block runs untracked, lives from `root` to `dispose`. Use it for a graph whose lifetime is an external event (a session, a connection). It both yields and returns the root.
- `dispose` and `disposed?` exist on effects and roots. Disposing walks the same teardown (children, then cleanups); an effect also severs every subscription. Calling it twice is harmless, and a disposed effect never runs again: not from a write, a batch it was queued in, or a late scheduler. Dispose always wins the race.

Full docs: https://planetaska.github.io/hibiki/lifecycle-in-detail/
