---
title: Advanced usage
nav_order: 4
---

# Advanced usage

So far the graph has looked after itself. Sometimes, you may want to change that behavior. For example, you may want to glance at a value without listening to it, or to make several writes count as one change. This page is about the moments when you want a say in the default arrangement.

## Untracked reads: reading without listening

An effect depends on everything it reads: that is usually the point. Now and then, though, an effect needs to *look* at a signal without *depending* on it. The clearest case is an effect that writes to a signal it also reads. Say you want a history of every value a counter has held:

```ruby
count   = state(0)
history = state([])

# Don't run this code. The effect reads history and then writes it, so its
# own write wakes it up again, creating an infinite loop.
effect { history.value = history.value + [count.value] }
```

The effect read `history`, so it depends on `history`. Then it wrote `history`, which is a change to something it depends on, so it runs again and never stops. What it wanted was the *current* contents of `history` with none of the attachment, and that is exactly what `peek` returns: the value, without the dependency.

```ruby
# The correct way to write an effect with self-referencing states
effect { history.value = history.peek + [count.value] }

count.value = 1
count.value = 2
history.value # => [0, 1, 2]
```

Now the effect depends on `count` alone. It runs once for every new count, reads the old history without subscribing to it, and writes the new one. A read-modify-write of this shape is the most common reason to reach for `peek`. The rule is simple: an effect should never depend on a signal it writes.

`peek` works one signal at a time. `Hibiki.untrack { }` does the same for a whole block: every read inside it goes unrecorded, and the block's result is returned to you. Here an effect reports who changed a counter, but only the counter should wake it:

```ruby
count = state(0)
user  = state("ada")

effect do
  who = Hibiki.untrack { user.value }
  puts "#{who} set the count to #{count.value}"
end                    # prints "ada set the count to 0"

user.value  = "grace"  # prints nothing
count.value = 1        # prints "grace set the count to 1"
```

Changing the user was silent, because the effect never depended on `user`. Changing the count printed the *new* user, because an untracked read still sees the live value. In the code above, `user.peek` would have the same effect. Reach for `untrack` when the reads come from several signals, or when they happen inside a method the effect calls rather than in the effect itself.

A `peek` on a derived still recomputes it when its value is stale, so the value you see is always fresh; only the dependency is left out. And `untrack` hides reads and nothing else: an effect created inside an `untrack` block still belongs to the effect around it, exactly as it would outside. Belonging is the subject of the [last section](#lifecycle-on_cleanup-and-root) on this page.

## Batching: several writes in one run

A write notifies the moment it happens. When two related values change together, that promptness works against you: an effect that reads both runs after the first write, sees a half-updated pair, and runs again after the second. Here a name is stored in two halves:

```ruby
first = state("Ada")
last  = state("Lovelace")
effect { puts "#{first.value} #{last.value}" } # prints "Ada Lovelace"

first.value = "Grace"  # prints "Grace Lovelace"
last.value  = "Hopper" # prints "Grace Hopper"
```

The first line is a name the program never meant to have: half old, half new, printed because the effect ran between two writes that belonged together. To have the effect wait until both have landed, wrap the writes in a batch. `batch { }` applies writes immediately but defers and deduplicates effect runs until the outermost batch exits. A read inside the block sees the new value at once, and the effect runs a single time, after the last write:

```ruby
batch do
  first.value = "Barbara"
  last.value  = "Liskov"
end # prints "Barbara Liskov", once
```

Under the hood, a single write is a batch of one. Here one signal reaches an effect along two paths, and the effect still runs once for the write, not once per path:

```ruby
n       = state(1)
doubled = derived { n.value * 2 }
squared = derived { n.value ** 2 }
effect { puts "#{doubled.value} and #{squared.value}" } # prints "2 and 1"

n.value = 3 # prints "6 and 9", once
```

`batch` widens that window to as many writes as you like. Batches nest, and only the outermost one flushes, so a method that batches its own writes can be called from inside another batch without causing a second run:

```ruby
batch do
  batch { first.value = "Margaret" }
  last.value = "Hamilton"
end # prints "Margaret Hamilton", once
```

A raise inside the block still flushes. The writes before it have already landed, and the effects catch up with them before the error reaches your rescue:

```ruby
begin
  batch do
    first.value = "Katherine"
    raise "something went wrong"
  end
rescue RuntimeError
  puts "rescued"
end # prints "Katherine Hamilton", then "rescued"
```

## Custom equality (`equals:`)

Writing a value equal to the one already held is a no-op, and an effect re-runs only when a value it read is actually different from last time. Both judgments use `==` by default, and `==` is often what is needed. However, some common cases break the assumption in different directions. For example, a sensor reading of 20.0 followed by 20.05 is, for some purposes, no change at all. The opposite happens with a signal that carries a message to show on screen. Save a document twice, and "Saved!" should appear twice, yet the second write is `==` to the first, so it is dropped and the second confirmation never shows. `equals:` lets each signal say what a change is. It takes three settings:

- Omitted or `nil`: the default behavior (`==`).
- A callable: your own comparator, called with the previous value and the new value. A truthy return means "unchanged", and the write is skipped.
- `false`: never equal. Every write notifies.

```ruby
# A tolerance: a write within 0.2 of the held value is skipped
temperature = state(20.0, equals: ->(prev, nxt) { (prev - nxt).abs < 0.2 })
effect { puts "temperature: #{temperature.value}" } # prints "temperature: 20.0"

temperature.value = 20.1 # prints nothing
temperature.value = 21.0 # prints "temperature: 21.0"

# A message to show: every write counts, repeats included
toast = state(nil, equals: false)
effect { puts "toast: #{toast.value}" if toast.value } # prints nothing yet

toast.value = "Saved!" # prints "toast: Saved!"
toast.value = "Saved!" # prints "toast: Saved!" again
```

`derived` accepts `equals:` too. If you pass a comparator, it compares each recomputed result with the last one, and an equal result skips every effect downstream.

```ruby
raw   = state(50.0)
peak  = state(100.0)
level = derived(equals: ->(a, b) { (a - b).abs < 0.01 }) { raw.value / peak.value }
effect { puts "level: #{level.value}" } # prints "level: 0.5"

raw.value = 50.1 # prints nothing: 0.501 is within a hundredth of 0.5
raw.value = 75.0 # prints "level: 0.75"
```

The comparator is consulted at both places where equality guards the graph: at the write, which decides whether a write is a no-op, and at the check an effect makes before it re-runs. Using the same comparison in both places is what makes the setting trustworthy. A change your comparator can see is never swallowed downstream.

Equality only ever sees assignments. If you take an array out of a signal, change it in place, and assign it back, the comparator will receive the same object on both sides, with no way to tell that anything changed:

```ruby
tags = state(["a"])
effect { puts "tags: #{tags.value.inspect}" } # prints "tags: [\"a\"]"

list = tags.value  # take an array out of a signal
list << "b"        # change the array in place
tags.value = list  # assigning it back prints nothing: the same object on both sides
```

`equals: false` is the one setting that still notifies here, because it never compares at all. The better fix is the one from Getting started: build a new array, `tags.value += ["b"]`, and let the signal see a value that is actually new.

## Lifecycle: `on_cleanup` and `root`

Real effects set things up: it could be a timer, a connection, or a subscription. Whatever an effect sets up must be released before the next run, and again when the effect is finished. `on_cleanup { }` registers a block for both moments, and `dispose` on the effect is what finishes it:

```ruby
topic = state("news")

watcher = effect do
  name = topic.value
  puts "subscribed to #{name}"
  on_cleanup { puts "unsubscribed from #{name}" }
end                      # prints "subscribed to news"

topic.value = "sports"   # prints "unsubscribed from news", then "subscribed to sports"
watcher.dispose          # prints "unsubscribed from sports"
topic.value = "weather"  # prints nothing
```

A disposed effect never runs again, even one already waiting in a batch.

An effect created inside another effect is owned by it, and disposed whenever the owner re-runs or is disposed; the panel in [Class-based reactivity]({% link _guides/class-based-reactivity.md %}#disposing-an-objects-effects) showed that. An effect at the top level has no owner. `root { }` gives it one: a scope that never re-runs, and takes down everything created inside it with one call:

```ruby
session = root do
  effect { puts "a sees #{topic.value}" }
  effect { puts "b sees #{topic.value}" }
end                      # prints "a sees weather", then "b sees weather"

topic.value = "local"    # prints "a sees local", then "b sees local"
session.dispose          # both effects are gone, cleanups included
topic.value = "sports"   # prints nothing
```

Hold the root for as long as the thing it stands for, such as a user's session or a connection, then dispose it. The block receives the root as its argument, for a graph that has to end itself from inside.

A root's block runs untracked. Build one inside an effect, and the reads inside the root do not become the effect's dependencies:

```ruby
page  = state("home")
theme = state("light")

effect do
  puts "showing #{page.value}"
  root { puts "theme is #{theme.value}" }
end                      # prints "showing home", then "theme is light"

theme.value = "dark"     # prints nothing
```

A root is also never adopted. Create one inside an effect, and disposing that effect leaves the root alone; it lives from `root` to `dispose`, and whoever holds it ends it:

```ruby
tick   = state(0)
ticker = nil

outer = effect { ticker = root { effect { puts "tick #{tick.value}" } } } # prints "tick 0"

outer.dispose            # the root was never adopted, so the ticker survives
tick.value = 1           # prints "tick 1"
ticker.dispose           # it is yours to end
tick.value = 2           # prints nothing
```

Outside any effect or root there is nothing to clean up after, so `on_cleanup` warns and registers nothing:

```ruby
on_cleanup { } # warning: no current owner (effect or root); the cleanup can never run
```

The [Lifecycle reference]({% link _references/lifecycle-in-detail.md %}) lays out the owner tree in full, including the exact order of teardown: children before their owner's cleanups, and cleanups last in, first out.

## Where to next

- [Lifecycle in detail]({% link _references/lifecycle-in-detail.md %}) walks the owner tree behind `on_cleanup` and `root`, rule by rule.
- [Threading model]({% link _references/threading-model.md %}) explains what Hibiki keeps per fiber, and what is and is not isolated across threads, fibers, and Ractors.
- [Why no transparent signals?]({% link _references/why-no-transparent-signals.md %}) covers the designs that would have hidden `.value`, and why each was rejected.
- [Status & limitations]({% link _references/status-and-limitations.md %}) lists what the signal core guarantees today.
