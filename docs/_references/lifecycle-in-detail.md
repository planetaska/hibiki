---
title: Lifecycle in detail
nav_order: 2
---

# Lifecycle in detail

An effect has a life. It is created and runs once. It runs again each time something it read has changed. Between runs it takes down whatever the previous run set up, and one day it is disposed and never runs again. This page describes each of those moments, who decides when it arrives, and what happens in it. The rules are few, and each comes with a small program you can run. The short version lives in the [Advanced usage guide]({% link _guides/advanced-usage.md %}#lifecycle-on_cleanup-and-root).

One important idea runs through this article: every effect, and every root, is an **owner**. Whatever gets created while its block runs, be it a child effect or a cleanup block, belongs to it and comes down with it. The owners form a tree, and the tree is what keeps a reactive program from leaking.

## The owner tree

While an effect is running its block, it is the *current owner*. An effect created during that window is adopted by it, and an adopted effect is disposed whenever its owner runs again or is disposed. Here an outer effect creates an inner one:

```ruby
mode  = state("day")
label = state("Sun")

effect do
  puts "mode is #{mode.value}"
  effect { puts "label is #{label.value}" }
end # prints "mode is day", then "label is Sun"

label.value = "Moon"  # prints "label is Moon": only the inner effect ran
mode.value  = "night" # prints "mode is night", then "label is Moon"
```

The last write is the interesting one. The outer effect ran again and created a new inner effect, which printed the label. The inner effect from the first run printed nothing, because it was disposed the moment its owner started over. Without adoption, every run of the outer effect would leave behind one more live copy of the inner one, and every label change would print once per copy, forever.

`Hibiki.untrack` does not interfere with any of this. It hides reads, and only reads. The owner stays in place, so an effect created inside an `untrack` block is adopted exactly as it would be outside.

## When an effect re-runs

An effect runs again when a value it read has changed, and only then. A write never runs an effect directly. It starts a short sequence, and the decision to run is made at the end of it, when the outermost batch closes. A plain write is a batch of one, so for a plain write the decision is made before the write returns:

1. **The write lands, or does not.** A write of an equal value returns early and notifies nobody. Equal means `==`, unless the signal was given an `equals:` of its own.
2. **Invalidation spreads.** Each derived downstream marks itself dirty and passes the news on. Each effect downstream is queued, once, however many paths the news arrived by.
3. **At the flush, every queued effect checks its sources.** It compares each value it read on its last run with that value now. A dirty derived recomputes here, to answer the question. If nothing differs, the effect stays put.

Here are all three steps on one small graph:

```ruby
count = state(0)
even  = derived { count.value.even? }
effect { puts "even? #{even.value}" } # prints "even? true"

count.value = 0 # step 1: an equal write, nobody hears of it
count.value = 2 # steps 2 and 3: even recomputes, true is still true, no run
count.value = 3 # prints "even? false"
```

The middle write is the one to notice. The count changed, the derived was marked dirty and the effect was queued, and still nothing printed. The flush recomputed `even`, found the same answer as last time, and let the effect be. The same value arriving by a new route is not a change.

This is the check Svelte's `$derived` makes. Hibiki makes it on the reading side, because by the time a derived knows its new value it has already told its subscribers to wake up. Two rules follow:

- **A derived's block must not have side effects.** The check may recompute a derived to learn whether it changed, and that recompute happens inside whichever effect asked. Anything the block creates or registers would belong to that effect. A derived is a value, not an owner.
- **`Effect#run` skips the check.** Calling `run` yourself runs the block, no questions asked. The [next section](#scheduled-re-runs) shows who calls it and why.

## Scheduled re-runs

By default the last step above runs the block then and there, inside the write that caused it. `effect(scheduler: ...)` replaces that step. When the flush decides the effect should run, Hibiki calls your scheduler with the effect instead of running it, and the effect waits until the scheduler calls `run` on it. The write still lands, invalidation still spreads, and the check at the flush still happens first:

```ruby
pending = []
count   = state(0)

effect(scheduler: ->(e) { pending << e }) do
  puts "count is #{count.value}"
end # prints "count is 0": the first run is never scheduled

batch do
  count.value = 1
  count.value = 2
end # prints nothing: the scheduler was called once, with the effect

pending.size    # => 1
pending.pop.run # prints "count is 2"
```

The first run happens at creation, scheduler or not, because that run is what collects the dependencies. After that the scheduler is called once per flush, however many writes the batch held, and a plain write is a batch of one. It is not called at all when the check finds nothing changed:

```ruby
handed = []
n      = state(1)
odd    = derived { n.value.odd? }

effect(scheduler: ->(e) { handed << e }) { puts "odd? #{odd.value}" } # prints "odd? true"

n.value = 3     # nothing to hand over: odd is still true
handed.size     # => 0
```

The scheduler's side of the contract is `run`. Call it when you are ready, on the thread the graph lives on, as the [Threading model]({% link _references/threading-model.md %}) explains. A run started this way skips the check, tears down and re-collects like any other run, and is a no-op once the effect has been disposed. An error raised by the block during such a run goes to whoever called `run`, since the run happens outside any flush.

A scheduler that raises is handled like an effect that raises: the flush finishes the rest of its queue, then re-raises the error, or hands it to `Hibiki.error_handler` when one is set.

This is how hibiki_rails merges a burst of changes into one broadcast. Its `Debounce` scheduler waits a short while, then calls `run` on the graph's own thread. [Phlex support]({% link _rails/phlex-support.md %}#deferring-re-renders) shows it in use.

## What a re-run tears down

Before an effect runs its block again, it undoes the previous run. Disposal does the same work. The order is fixed:

1. **Owned children are disposed first**, so a child's cleanup can still use a resource that its owner's cleanup is about to release.
2. **The owner's own cleanups run**, newest first. Last in, first out, like nested `ensure` blocks.
3. **Dependencies are collected afresh.** This step belongs to a re-run only. The block runs again and subscribes to exactly what it reads this time.

The first two steps, made visible:

```ruby
tick = state(0)
log  = []

effect do
  tick.value
  on_cleanup { log << "outer, first" }
  effect { on_cleanup { log << "child" } }
  on_cleanup { log << "outer, second" }
end

tick.value = 1
log # => ["child", "outer, second", "outer, first"]
```

The child went first, then the outer effect's two cleanups in reverse order. The third step is what makes a dependency that comes and goes behave. An effect that reads one signal or another, depending on a flag, listens to only the branch it took last:

```ruby
flag = state(true)
a    = state("a")
b    = state("b")

effect { puts(flag.value ? a.value : b.value) } # prints "a"

b.value    = "B"   # prints nothing: the last run never read b
flag.value = false # prints "B"
a.value    = "A"   # prints nothing: the last run read flag and b
```

After the flag flipped, `a` stopped mattering, and a write to it no longer wakes the effect. The stale branch was forgotten along with everything else the previous run read.

## `on_cleanup`

`on_cleanup { }` registers a teardown block on the current owner, the innermost effect or root that is running. The block runs before the owner's next re-run and again when the owner is disposed. That makes it the home for anything an effect acquires:

```ruby
url = state("wss://a.example")

effect do
  socket = connect(url.value)
  on_cleanup { socket.close } # the old socket closes before each reconnect
end

url.value = "wss://b.example" # closes the socket to a, then opens one to b
```

Two details are worth knowing. First, the owner is a separate slot from the tracking listener. A lazy derived that happens to recompute in the middle of an effect registers its `on_cleanup` calls on the *effect*, because a derived is a value and never owns anything. Second, outside any effect or root the block could never run, so Hibiki warns and drops it rather than raising:

```ruby
on_cleanup { } # warning: no current owner (effect or root); the cleanup can never run
```

## Roots escape the tree

`root { }` is the deliberate exception to adoption. A root created inside a running effect is **not** adopted by it, and the root's block runs untracked, so the signals it reads while building its graph do not subscribe the enclosing effect. A root lives from `root` to `dispose`, wherever it was created:

```ruby
watcher = state(0)
session = nil

effect do
  puts "watching #{watcher.value}"
  session ||= root do
    effect { puts "still alive" }
  end
end # prints "watching 0", then "still alive"

watcher.value = 1 # prints "watching 1": the root and its effect are untouched
session.dispose   # the only way this graph comes down
```

The outer effect re-ran and the inner effect did not, because the inner effect belongs to the root, and the root belongs to nobody but the variable holding it. That is the escape hatch from the owner tree, and it is what you want for a graph whose lifetime is an external event, such as a user's session or a connection, rather than a re-run.

`root { |root| ... }` both yields the root and returns it, since in Ruby the caller, not the block, typically holds on to it.

## Disposal is final

Roots and effects both respond to `dispose` and `disposed?`. Disposing walks the same teardown as a re-run, children first and then cleanups, and an effect additionally severs every subscription, so nothing can invalidate it again.

`dispose` can be called twice without harm, and a disposed effect never runs again under any circumstance: not from a write, not from a batch it was already waiting in, and not from a scheduler firing a deferred re-run late. Dispose always wins the race:

```ruby
count  = state(0)
logger = effect { puts "count is #{count.value}" } # prints "count is 0"

batch do
  count.value = 1
  logger.dispose
end # prints nothing: the effect was queued, and dispose won
```

You rarely need `dispose` on an effect directly. The owner tree handles nested effects, and roots handle everything long-lived. It is there for the odd effect whose lifetime matches neither.
