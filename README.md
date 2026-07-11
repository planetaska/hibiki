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

## Status & limitations

Hibiki is a young signal core. Known gaps, in the order they'll be addressed:

1. **Stale subscriptions** — recomputing does not yet unsubscribe from old
   dependencies (Solid clears dependency lists before each rerun; we'll
   mirror that).
2. **Batching** — multiple writes should coalesce effect runs.
3. **Glitch freedom** — diamond-shaped graphs may run effects with
   inconsistent intermediate values.
4. **Effect disposal** — `Effect#dispose` and ownership scopes.
5. **Thread safety** — the observer stack is currently global.

## Development

```sh
bundle install
bundle exec rake     # specs + rubocop
ruby demo.rb         # quick smoke demo
```

## License

[MIT](LICENSE.txt)
