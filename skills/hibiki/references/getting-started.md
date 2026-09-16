# Getting started

Ruby >= 3.4, no runtime dependencies. `gem "hibiki"` in the Gemfile, or `gem install hibiki`.

## Two flavors, same objects

| Style | Spelling | When |
|---|---|---|
| DSL | `include Hibiki::DSL`, then `state(v)`, `derived { }`, `effect { }`, `batch { }`, `root { }`, `on_cleanup { }` | scripts, specs, classes that want the short names |
| Classes | `Hibiki::State.new(v)`, `Hibiki::Derived.new { }`, `Hibiki::Effect.new { }`, `Hibiki.batch`, `Hibiki.root`, `Hibiki.on_cleanup` | libraries; nothing added to callers' namespace |

The DSL is strictly opt-in; requiring the gem never includes it. The two styles mix freely.

## The three primitives

| Primitive | What it is | API |
|---|---|---|
| `state(v)` | a writable signal; reads register the reader, writes notify | `value`, `value=`, `update { it + 1 }`, `peek`, `call` |
| `derived { }` | a read-only signal computed from what its block reads; cached, lazy | `value`, `peek`, `call` |
| `effect { }` | runs at creation, and again whenever a value it read has changed | `dispose`, `disposed?`, `run` |

```ruby
counter = state(0)
doubled = derived { counter.value * 2 }
effect { puts "doubled is #{doubled.value}" }   # prints "doubled is 0"

counter.value += 1                              # prints "doubled is 2"
counter.update { it + 1 }                       # prints "doubled is 4"
```

Rules that follow from the design:

- Writing an equal value (`==`, or the signal's `equals:`) is a no-op: nobody is notified.
- A derived recomputes on the next read after a source changed, never at the write, and never if nobody reads it. Chain them as deep as you like.
- An effect re-runs only when a value it read is actually different from last time.
- Dependencies are re-collected on every run, so `flag.value ? a.value : b.value` listens to the branch it took last.

## Collections: assign, do not mutate

Hibiki sees assignments and nothing else. `todos.value << item` changes the array in place and no signal hears about it.

```ruby
todos     = state([])
remaining = derived { todos.value.count { !it[:done] } }
effect { puts "#{remaining.value} left to do" }            # prints "0 left to do"

todos.value += [{ title: "Read the docs", done: false }]   # prints "1 left to do"
todos.value = todos.value.map { it.merge(done: true) }     # prints "0 left to do"
```

Build the new array or hash, then assign it. See `mutable-defaults.md` for the method table.

## Next

- `class-based-reactivity.md` for signals as class attributes without `.value`.
- `advanced-usage.md` for `peek`, `untrack`, `batch`, `equals:`, `on_cleanup`, `root`.

Full docs: https://planetaska.github.io/hibiki/getting-started/
