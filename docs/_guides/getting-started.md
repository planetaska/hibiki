---
title: Getting started
nav_order: 2
---

# Getting started

Hibiki has no runtime dependencies and requires Ruby >= 3.4.

## Installation

```ruby
# Gemfile
gem "hibiki"
```

Or install it directly:

```sh
gem install hibiki
```

## Two flavors

The DSL gives you bare `state` / `derived` / `effect` helpers. It is strictly
opt-in — the gem never includes it for you:

```ruby
require "hibiki"
include Hibiki::DSL

x = state(0)
y = derived { x.value + 1 }
```

Prefer no DSL? Use the classes directly — they are the same objects:

```ruby
require "hibiki"

x = Hibiki::State.new(0)
y = Hibiki::Derived.new { x.value + 1 }

x.value = 10
y.value # => 11
```

## The three primitives

**`state(v)`** — a writable signal. Reading `.value` registers a dependency;
writing notifies subscribers. Writing an `==`-equal value is a no-op.

```ruby
counter = state(0)
counter.value += 1
counter.update { it + 1 } # in-place sugar
```

**`derived { }`** — a lazy computed signal. It recomputes on read when marked
dirty, never on write, and caches its value until a dependency changes.

```ruby
doubled = derived { counter.value * 2 }
doubled.value # => 4
```

**`effect { }`** — an eager side effect. It runs immediately and re-runs
whenever a dependency changes.

```ruby
name = state("world")
effect { puts "hello, #{name.value}!" } # prints "hello, world!"

name.value = "Ruby"                     # prints "hello, Ruby!"
```

## Untracked reads

Sometimes an effect should *sample* a signal without depending on it.
`Hibiki.untrack { }` suppresses dependency registration for a block, and
`#peek` is the per-signal shorthand — the classic use is read-modify-write,
where an effect must not depend on the signal it writes:

```ruby
count = state(0)
history = state([])

# Log every count change — without peek, writing history would re-trigger
# this effect forever (it would depend on its own output).
effect { history.value = history.peek + [count.value] }
```

## Batching

`batch { }` (or `Hibiki.batch { }`) applies writes immediately but defers and
deduplicates effect runs until the outermost batch exits — several related
writes trigger each affected effect once, not once per write:

```ruby
first = state("Ada")
last  = state("Lovelace")
effect { puts "#{first.value} #{last.value}" } # prints "Ada Lovelace"

batch do
  first.value = "Grace"
  last.value  = "Hopper"
end # prints "Grace Hopper" — once, not twice
```

## Class-based reactivity

Svelte 5 allows `$state` / `$derived` / `$effect` as class fields;
`Hibiki::Reactive` is the Ruby analogue. Declare signals with class macros and
use them as plain attributes — no `.value` at usage sites:

```ruby
class Counter
  include Hibiki::Reactive

  state :count, 0
  state(:history) { [] }          # block form: fresh default per instance
  derived(:doubled) { count * 2 }
  effect { puts "count is now #{count}" } # starts on Counter.new

  def increment = self.count += 1
end

counter = Counter.new  # prints "count is now 0"
counter.increment      # prints "count is now 1"
counter.doubled        # => 2
```

Signals are per-instance and created lazily; subclasses inherit all
declarations. Use the block form for mutable defaults (a positional default
is one shared object, the same gotcha as Rails attribute defaults).

## Where to next

- [Threading model]({{ "/threading-model/" | relative_url }}) —
  fiber-confined bookkeeping, what is and isn't isolated across threads,
  fibers, and Ractors.
- [Why no transparent signals?]({{ "/why-no-transparent-signals/" | relative_url }}) —
  the rejected transparency designs, with the failure cases spelled out.
- [Status & limitations]({{ "/status-and-limitations/" | relative_url }}) —
  what the signal core already guarantees.
