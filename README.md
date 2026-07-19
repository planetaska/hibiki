# Hibiki (響き) — Svelte-5-style signals for Ruby

Svelte-5-style signals for Ruby: `state`, `derived`, `effect`.

Hibiki is a fine-grained reactivity library modeled on the signal systems in [Svelte 5](https://svelte.dev/docs/svelte/what-are-runes) and [SolidJS](https://www.solidjs.com/guides/reactivity). Dependency tracking is done at **runtime** (not by static AST analysis): while a derived value or effect is computing, it sits on an observer stack, and any signal read during that window subscribes it.

No runtime dependencies. Requires Ruby >= 3.4.

## Installation

```ruby
# Gemfile
gem "hibiki"
```

Or `gem install hibiki`.

## Usage

You can use Hibiki in two flavors:

```ruby
# 1. With DSL
require "hibiki"
include Hibiki::DSL

x = state(0)
y = derived { x.value + 1 }

x.value = 10
y.value # => 11
```

Or if you wish to avoid using DSL:

```ruby
# 2. Without DSL
require "hibiki"

x = Hibiki::State.new(0)
y = Hibiki::Derived.new { x.value + 1 }

x.value = 10
y.value # => 11
```

### The three primitives

**`state(v)`** — a writable signal. Reading `.value` registers a dependency; writing notifies subscribers. Writing an `==`-equal value is a no-op.

```ruby
counter = state(0)
counter.value += 1
counter.update { it + 1 } # in-place sugar
```

**`derived { }`** — a lazy computed signal. It recomputes on read when marked dirty (when any state it depends on changes), never on write, and caches its value until a dependency changes.

```ruby
doubled = derived { counter.value * 2 }
doubled.value # => 4
```

**`effect { }`** — an eager side effect. It *runs immediately* and re-runs whenever a dependency (any state inside the effect block) changes.

```ruby
name = state("world")
effect { puts "hello, #{name.value}!" } # prints "hello, world!"

# Effect triggers whenever any of the subscribed values changes
name.value = "Ruby"                     # prints "hello, Ruby!"
```

### Dynamic dependencies

Dependencies are re-collected on every recompute, so conditional reads work:

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

### Class-based reactivity

Svelte 5 allows `$state` / `$derived` / `$effect` as class fields; `Hibiki::Reactive` is the Ruby analogue. Declare signals with class macros and use them as plain attributes — no more `.value` in code:

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

Signals are per-instance and created lazily; subclasses inherit all declarations. Use the block form for mutable defaults — a positional default is one object shared by every instance; see [Mutable state defaults](docs-md/mutable-defaults.md) for the details.

## Documentation

Documentation site: <https://planetaska.github.io/hibiki/>

More detail in plain markdown: [docs-md/](docs-md/)

## Development

```sh
bundle install
bundle exec rake     # specs + rubocop
ruby demo.rb         # quick smoke demo
```

## License

[MIT](LICENSE.txt)
