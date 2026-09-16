---
name: hibiki
description: >-
  Svelte-5-style signals for Ruby: Hibiki::State, Hibiki::Derived, Hibiki::Effect, Hibiki.root, Hibiki.batch, Hibiki.untrack, peek, on_cleanup, equals:, scheduler:, the opt-in Hibiki::DSL (bare state/derived/effect) and the Hibiki::Reactive class macros. Load whenever Ruby code reads or writes .value, includes Hibiki::DSL or Hibiki::Reactive, or a derived/effect "does not update", loops forever, raises SystemStackError, a <<-mutated array or merge!-ed hash stays stale, or threads, fibers, Sidekiq/Puma or Ractors touch a signal graph. Also the family router: read its "Which skill next" table, then load hibiki-rails (channels, islands, JS client, ActiveRecord), hibiki-rails-forms (ReactiveForm, app/forms), hibiki-rails-scaffold (every bin/rails g hibiki:rails:* generator), hibiki-rails-motion (data-motion, hbk-* CSS) or hibiki-phlex (Phlex components). Do not stop here for anything under app/channels, app/forms, or a hibiki:rails generator.
license: MIT
metadata:
  author: planetaska
  hibiki: "0.3.0"
  hibiki_rails: "0.15.0"
  hibiki_phlex: "0.1.0"
---

# hibiki: signals for Ruby

## What hibiki is

Hibiki (響き) brings signals, the reactive primitive behind Svelte 5 and SolidJS, to plain Ruby. A signal is a value that remembers who read it. `state` holds a value, `derived` computes one from other signals, and `effect` runs a block now and again whenever a value it read has changed. Dependencies are collected at runtime from reads, never declared, so a block such as `flag.value ? a.value : b.value` follows the branch it took last. Pure Ruby, no runtime dependencies, Ruby >= 3.4.

```ruby
require "hibiki"
include Hibiki::DSL

price    = state(100)
quantity = state(2)
total    = derived { price.value * quantity.value }

effect { puts "Total: $#{total.value}" }  # prints "Total: $200"

quantity.value = 3                        # prints "Total: $300"
price.value    = 50                       # prints "Total: $150"
```

## Which skill next

This skill covers the core gem only. Match the task against the table before reading on, because the Rails, form, generator, motion and Phlex surfaces live in sibling skills and nothing below describes them.

| You are looking at | Load |
|---|---|
| `app/channels/*_channel.rb` with `Hibiki::Rails::Channel`, `build_graph`, `transmit`, `transmit_value`, `broadcast_replace`/`broadcast_morph` | `hibiki-rails` |
| `island`, `hibiki_island`, `on(...)`, `reactive`, `reactive_attrs` in a view | `hibiki-rails` |
| The JS client: `HibikiController`, `ChannelController`, `performOn`, `data-hibiki-*`, `fallback:`, `visible`, `streamConnected` | `hibiki-rails` |
| ActiveRecord in a graph, `record_equals`, after_commit pings, "page does not update", "first update never arrives", "button does nothing" | `hibiki-rails` |
| `Hibiki::Rails::ReactiveForm`, `app/forms/*_form.rb`, `commit`, nested fieldsets, multi-select, Active Storage uploads | `hibiki-rails-forms` |
| Any `bin/rails g hibiki:rails:*` (install, scaffold, scaffold_controller, stimulus, island, phlex) and its options | `hibiki-rails-scaffold` |
| The add-on generators `form`, `nested`, `multiselect`, `upload_field` | `hibiki-rails-scaffold` to invoke; `hibiki-rails-forms` for what they write |
| `data-motion`, `data-motion-leaving`, `hbk-slide`/`hbk-fade`/`hbk-fly`/`hbk-scale`/`hbk-blur`, `hibiki_motion.css`, `--skip-motion` | `hibiki-rails-motion` |
| A `Phlex::HTML` component including `Hibiki::Reactive`, `render_effect`, `Rerenderable`, `DoubleRenderError` | `hibiki-phlex` |

The scaffold's `--phlex` flag belongs to `hibiki-rails-scaffold`, not `hibiki-phlex`: it writes stateless Phlex views driven by a channel and never pulls in the hibiki_phlex gem.

## Family and versions

This is the one shared versions table; sibling skills point here instead of repeating it.

| Package | Version | Notes |
|---|---|---|
| `hibiki` gem | 0.3.0 | the core; no runtime dependencies |
| `hibiki_rails` gem | 0.15.0 | Rails >= 8.0 (`actioncable`, `railties`), `turbo-rails >= 2.0`, `hibiki ~> 0.3` |
| `hibiki-rails` npm | 0.15.0 | lockstep with the gem, so pin both to the same number; peers `@hotwired/stimulus >= 3.2`, `@hotwired/turbo-rails >= 8.0` |
| `hibiki_phlex` gem | 0.1.0 | deps hibiki + phlex only; strict pin `phlex >= 2.4, < 2.5` |

Ruby >= 3.4 for all three gems. Docs root: https://planetaska.github.io/hibiki/

## Two flavors

Use either spelling; they build the same objects. `include Hibiki::DSL` adds bare `state`, `derived`, `effect`, `batch`, `root` and `on_cleanup` to the including scope. Requiring the gem never includes it for you, so a library built on hibiki adds nothing to its callers' namespace; include it yourself where you want the short names.

```ruby
require "hibiki"

x = Hibiki::State.new(0)
y = Hibiki::Derived.new { x.value + 1 }
Hibiki::Effect.new { puts y.value }   # prints 1
x.value = 10                          # prints 11
```

## Three primitives

| Class | Create | Read | Write | Lifecycle |
|---|---|---|---|---|
| `Hibiki::State` | `State.new(value, equals: nil)` / `state(v)` | `value` (tracks), `peek` (no edge), `call` | `value=`, `update { it + 1 }` | none; garbage collected |
| `Hibiki::Derived` | `Derived.new(equals: nil) { }` / `derived { }` | `value` (tracks), `peek`, `call` | none, read-only | no `dispose`, no owner; stays subscribed to its sources |
| `Hibiki::Effect` | `Effect.new(scheduler: nil) { }` / `effect { }` | runs at creation, collects deps | | `dispose`, `disposed?`, `run` (bypasses the gate), `invalidate` |

Three rules govern the graph, and most bugs trace back to one of them:

- A write of an equal value is a no-op: nobody is notified, nothing downstream runs. Equal means `==` unless the signal's `equals:` says otherwise.
- A derived is lazy: a write marks it dirty and nothing more; its block runs on the next read, and never if nobody reads it.
- An effect re-runs only when a value it read is actually different from last time, checked at the batch flush by each source's equality. Nothing else re-runs it, and `Effect#run` deliberately skips that check.

Assign, never mutate in place: `todos.value += [item]`, not `todos.value << item`, because the signal sees assignments and nothing else.

## Class-based reactivity

`include Hibiki::Reactive` puts a per-instance signal behind each attribute, so reads and writes drop the `.value` and tracking flows through plain method calls (Svelte 5's class fields).

```ruby
class Counter
  include Hibiki::Reactive

  state :count, 0
  state(:history) { [] }              # block default: fresh per instance
  derived(:doubled) { count * 2 }
  effect { puts "count is now #{count}" }

  def increment = self.count += 1     # `count += 1` would make a local
end
```

- `state :name, default, equals: nil` defines reader and writer; `derived(:name, equals: nil) { }` a reader; `effect { }` is anonymous.
- Give the writer an explicit receiver (`self.count = 1`), because a bare `count = 1` is a local variable to the Ruby parser.
- Put a mutable default in a block, because a positional default is one object made when the class body runs and shared by every instance. The block runs with the instance as `self` and untracked, so a default that reads another attribute does not subscribe the effect that first touched it.
- Effects start after your own `initialize` returns, so they see the finished object, never the defaults.
- Signals are created lazily on first touch; subclasses inherit every declaration, and inherited effects start alongside the subclass's own.
- Call `dispose` on an instance whose effects read a signal outside itself, because that signal keeps the effect alive after your last reference is gone. Instances created inside a running effect are adopted and need no call.

## Untracked reads, batching, equality

Read without subscribing when an effect writes what it reads, because depending on your own write re-runs the effect forever. `peek` does it for one signal; `Hibiki.untrack { }` for a whole block (reads only; the owner slot is untouched, so effects created inside are still adopted). A `peek` on a dirty derived still recomputes it, so the value is fresh.

```ruby
effect { history.value = history.peek + [count.value] }   # depends on count alone
```

`Hibiki.batch { }` applies writes immediately and defers effect runs, deduplicated, until the outermost batch exits. Batches nest and only the outermost flushes; a raise inside still flushes, because the writes before it have landed; a plain write is a batch of one, which is why a diamond runs its effect once per write.

`equals:` on `state` and `derived` takes three settings, and both gates consult it (the write gate in `State#value=` and the flush gate the effect asks before re-running), so a change your comparator can see is never swallowed downstream:

| `equals:` | Meaning |
|---|---|
| omitted / `nil` | `==` |
| callable `(prev, next)` | truthy means unchanged, so the write is skipped |
| `false` | never equal; every write notifies (toasts, "look again" on a mutated buffer) |

```ruby
temperature = state(20.0, equals: ->(prev, nxt) { (prev - nxt).abs < 0.2 })
toast       = state(nil, equals: false)
```

## Lifecycle

Every effect and every root is an owner. Effects and `on_cleanup` blocks created while its block runs belong to it and come down when it re-runs or is disposed. Teardown order is fixed: owned children first, then the owner's cleanups newest first, then (on a re-run only) the block runs again and re-collects its dependencies.

- `on_cleanup { }` registers on the current owner (the innermost running effect or root, never a derived). Outside any owner it warns `Hibiki.on_cleanup: no current owner (effect or root); the cleanup can never run` and drops the block.
- `Hibiki.root { |root| }` is an ownership scope that is not an effect: it never re-runs, its block runs untracked, it is never adopted by an enclosing effect, and it both yields and returns the root. Hold it for a session or a connection and `dispose` it yourself.
- `dispose` is final and idempotent: a disposed effect never runs again, not from a write, a pending batch, or a late scheduler.
- `effect(scheduler: ->(e) { ... })` hands re-runs to your callable after the flush gate has said something changed; call `e.run` on the graph's thread when ready. The first run is never scheduled, because it collects the dependencies. A raise inside a scheduled `run` reaches whoever called `run`.
- `Hibiki.error_handler = ->(error, effect) { }` takes errors raised by effects during a flush; the flush finishes its queue first. It is per Ractor, set once, seen by every thread.

## Threading model

- Tracking window and current owner live in `Fiber[]`, which new fibers inherit, so a read inside an `Enumerator` or an async task still registers its edge.
- Batch depth and queue live in `Thread.current[]`, which new fibers start empty, so a fiber spawned mid-batch writes eagerly instead of waiting on a flush that never comes.
- Signals hold no locks. Give each graph one thread and send it messages (a `Queue` and one owner thread; hibiki_rails posts each action to the graph's own thread).
- Each Ractor runs an independent reactive world with its own `error_handler`; signals never cross the boundary.

## Pitfalls

- In-place mutation is not a write. `<<`, `push`, `merge!`, `sub!` change the object without touching the writer, so nothing is notified; assign a fresh object instead. (getting-started, mutable-defaults)
- Assigning the same object back is dropped. The writer compares by `==`, and a mutated object equals itself, so `prices = prices.merge!(...)` is a no-op. Use `merge`, `+`, `reject`, or `Data#with`; `equals: false` if a copy is too costly. (mutable-defaults)
- Equal writes never notify, and an effect re-runs only when a value it read differs. A count going 0 to 2 leaves `even?` unchanged and the effect quiet. (lifecycle-in-detail)
- A derived recomputes on read only, and one with no signal read computes once forever. `derived { Todo.where(done: false).count }` caches the first count for the life of the graph. (working-with-active-record, in `hibiki-rails`)
- A derived has no `dispose` and no owner. Create it once beside the states it reads, because it stays subscribed for as long as they live, and keep its block free of side effects, because an effect or cleanup created inside belongs to whichever effect happened to read it. (status-and-limitations)
- No gate on deriveds downstream. A derived that recomputes to an equal value still marks the deriveds below it stale; only effects are gated. (status-and-limitations)
- An effect that writes a signal it reads raises `SystemStackError`. There is no cycle detection; read what you write through `peek` or `untrack`. (advanced-usage)
- A positional mutable default is one shared object. `state :entries, []` hands every instance the same array; use `state(:entries) { [] }`. (class-based-reactivity)
- `count = 1` inside a method creates a local. The signal writer needs `self.count = 1`. (class-based-reactivity)
- Reactive effects start after `initialize`, not before, so a constructor that expects an effect's side effect to have happened already is wrong. (class-based-reactivity)
- An object whose effects read outside signals outlives your references. The outside signal holds the effect; call `dispose` while you still hold the object. (class-based-reactivity)
- A root escapes adoption, and `on_cleanup` outside an owner warns and drops. Disposing the enclosing effect leaves a root alone by design. (lifecycle-in-detail)
- A graph is thread-confined, batches are not inherited by fibers, and the tracking window is. Writes from another thread go through a queue to the owner thread. (threading-model)
- `Hibiki.error_handler` sees only flush re-runs. A raise on the first run leaves `Effect.new`; a raise inside a scheduled `run` reaches the caller of `run`. (status-and-limitations)
- `Effect#run` skips the equality gate, so calling it yourself runs the block unconditionally. (lifecycle-in-detail)
- Nothing is deferred to a later tick and there is no async primitive. Wait outside the graph, then write the result into a state. (status-and-limitations)
- No `method_missing` wrapper and no bare-variable block DSL. A wrapper is always truthy in `if`, and `count = 1` is never a method call; both designs are rejected, so do not propose them. (why-no-transparent-signals)
- The DSL is opt-in. `require "hibiki"` defines no bare `state`; `include Hibiki::DSL` where you want it. (getting-started)

## Reference files

- `references/getting-started.md`: install, the two flavors, the three primitives with their one-line rules.
- `references/class-based-reactivity.md`: the `Hibiki::Reactive` macros, defaults, effect start, inheritance, `dispose`.
- `references/advanced-usage.md`: `peek` vs `untrack`, batch semantics, the `equals:` table, `on_cleanup` and `root`.
- `references/lifecycle-in-detail.md`: owner tree, the three-step re-run decision, teardown order, `scheduler:`, disposal.
- `references/threading-model.md`: what lives in `Fiber[]` vs `Thread.current[]`, one graph per thread, the `Queue` pattern, Ractors.
- `references/mutable-defaults.md`: positional vs block defaults, destructive to copying method table, `Data#with`, `equals: false`.
- `references/status-and-limitations.md`: what 0.3.0 guarantees and what it leaves to you.
- `references/why-no-transparent-signals.md`: why there is no transparent wrapper or bare-variable DSL.

## Related skills

- `hibiki-rails`: channels, islands, the JS client, broadcasts, ActiveRecord patterns, troubleshooting.
- `hibiki-rails-forms`: `ReactiveForm`, nested collections, multi-select, file uploads.
- `hibiki-rails-scaffold`: the `hibiki:rails:*` generators and their options, including `--phlex`.
- `hibiki-rails-motion`: enter/leave transitions with `data-motion` and the `hbk-*` utilities.
- `hibiki-phlex`: reactive Phlex components with `render_effect` and `Rerenderable`.
