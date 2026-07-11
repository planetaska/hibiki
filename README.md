# Hibiki (響き)

Svelte-5-style signals for Ruby: `state`, `derived`, `effect`.

Hibiki is a fine-grained reactivity library modeled on the signal systems in
[Svelte 5](https://svelte.dev/docs/svelte/what-are-runes) and
[SolidJS](https://www.solidjs.com/guides/reactivity). Dependency tracking is
done at **runtime**, not by static analysis: while a derived value or effect
is computing, it sits on an observer stack, and any signal read during that
window subscribes it. That's what makes dynamic dependencies work.

No runtime dependencies. Requires Ruby >= 3.4.

## Installation

```ruby
# Gemfile
gem "hibiki"
```

Or `gem install hibiki`.

## Usage

```ruby
require "hibiki"

x = Hibiki::State.new(0)
y = Hibiki::Derived.new { x.value + 1 }

x.value = 10
y.value # => 11
```

Or opt into the bare DSL helpers wherever you like — Hibiki never includes
anything for you:

```ruby
include Hibiki::DSL

x = state(0)
y = derived { x.value + 1 }
```

### The three primitives

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

### Dynamic dependencies

Dependencies are re-collected on every recompute, so conditional reads work —
the thing static analysis can't do:

```ruby
flag = state(true)
a = state("A")
b = state("B")
picked = derived { flag.value ? a.value : b.value }

picked.value        # => "A"
b.value = "B2"      # picked doesn't depend on b right now — no recompute
flag.value = false
picked.value        # => "B2" (deps re-collected)
```

## Threading model

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

## Status & limitations

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
- **Execution-context isolation** — see the threading model above.

Known gaps, in the order they'll be addressed:

1. **Ergonomics experiments** — transparent access, a `reactive` DSL.

## Development

```sh
bundle install
bundle exec rake     # specs + rubocop
ruby demo.rb         # quick smoke demo
```

## License

[MIT](LICENSE.txt)
