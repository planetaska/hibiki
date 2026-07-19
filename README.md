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

**`derived { }`** — a lazy computed signal. It recomputes on read when marked dirty, never on write, and caches its value until a dependency changes.

```ruby
doubled = derived { counter.value * 2 }
doubled.value # => 4
```

**`effect { }`** — an eager side effect. It runs immediately and re-runs whenever a dependency changes.

```ruby
name = state("world")
effect { puts "hello, #{name.value}!" } # prints "hello, world!"

# Effect triggers whenever any of the subscribed values changes
name.value = "Ruby"                     # prints "hello, Ruby!"
```

### Untracked reads

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

A dirty derived still recomputes on `peek`; only the reader's subscription is
skipped. Signals also respond to `#call`, mirroring Solid's
signals-as-getter-functions: `count.call` (or `count.()`) reads and registers.

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

### Lifecycle: `root` and `on_cleanup`

Effects created while another effect runs are *owned* by it and disposed
automatically when the owner re-runs or is disposed. For everything else
there is `Hibiki.root` (Solid's `createRoot`): an ownership scope you tear
down yourself — the anchor for long-lived graphs (a session, a connection)
whose teardown is an external event, not a rerun.

`Hibiki.on_cleanup` (Solid's `onCleanup`) registers teardown on the owning
effect or root; it runs before each re-run and on dispose — the place to
release timers, sockets, subscriptions an effect sets up:

```ruby
interval = state(1)

ticker = Hibiki.root do
  effect do
    timer = start_timer(every: interval.value)
    Hibiki.on_cleanup { timer.cancel } # runs before each re-run, and on dispose
  end
end

interval.value = 5 # old timer cancelled, new one started
ticker.dispose     # tears down every effect in the scope, cleanups included
```

A root's block runs untracked, and a root created inside an effect is *not*
adopted by it — it deliberately escapes the automatic owner tree, so its
lifetime is exactly `Hibiki.root` … `root.dispose`. Individual effects can
still be disposed directly with `Effect#dispose`.

### Class-based reactivity

Svelte 5 allows `$state`/`$derived`/`$effect` as class fields; `Hibiki::Reactive`
is the Ruby analogue. Declare signals with class macros and use them as plain
attributes — no `.value` at usage sites:

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

Effect lifecycle: an instance created *inside* a running effect is adopted by
the owner tree and cleaned up automatically when that owner re-runs or is
disposed. For long-lived instances whose effects read signals *outside* the
instance, call `#dispose` — effects that only read the instance's own signals
form a self-contained island that garbage-collects with it.

### Why no transparent signals?

Two designs were evaluated and rejected, so they don't need relitigating:

- **Transparent value wrappers** (`method_missing` forwarding to `.value`):
  Ruby object truthiness cannot be overridden, so `if flag` on a wrapper is
  always true — it silently breaks conditionals, the exact thing dynamic
  dependency tracking is best at. `nil?` and `==` lie similarly.
- **A `reactive do ... end` block DSL**: Ruby has no hook for bare local
  variable reads or writes, so writes need `self.x =` anyway — at which point
  a class (above) wears the same design better.

The full walkthrough with examples lives in
[docs-md/why-no-transparent-signals.md](docs-md/why-no-transparent-signals.md).

## Documentation

Browsable documentation site: <https://planetaska.github.io/hibiki/>

More detail in [docs-md/](docs-md/):

- [Why no transparent signals?](docs-md/why-no-transparent-signals.md) — the two
  rejected transparency designs, with the failure cases spelled out.
- [Threading model](docs-md/threading-model.md) — fiber-confined bookkeeping,
  what is and isn't isolated across threads, fibers, and Ractors.
- [Lifecycle in detail](docs-md/lifecycle-in-detail.md) — the owner tree:
  effect adoption, cleanup ordering, roots, and disposal semantics.
- [Status & limitations](docs-md/status-and-limitations.md) — what the signal
  core already guarantees.
- [Fragment-level render effects](docs-md/fragment-level-render-effects.md) —
  a deferred design note: collapsing per-fragment partials/components into
  methods, each wrapped in its own effect.

## Development

```sh
bundle install
bundle exec rake     # specs + rubocop
ruby demo.rb         # quick smoke demo
```

## License

[MIT](LICENSE.txt)
