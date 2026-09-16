# Class-based reactivity

`include Hibiki::Reactive` puts a signal behind each declared attribute. Readers and writers are ordinary methods (`define_method`), so a read like `count` tracks exactly as `count.value` would, and there is no `.value` at the point of use. This is the Ruby analogue of Svelte 5's `$state`/`$derived`/`$effect` class fields.

```ruby
class Counter
  include Hibiki::Reactive

  state :count, 0
  derived(:doubled) { count * 2 }
  effect { puts "count is now #{count}" }

  def increment = self.count += 1
end

counter = Counter.new  # prints "count is now 0"
counter.increment      # prints "count is now 1"
counter.doubled        # => 2
```

## The three macros

| Macro | Defines | Notes |
|---|---|---|
| `state :name, default = nil, equals: nil` or `state(:name, equals: nil) { default }` | reader + writer over a `State` | block default runs per instance, as `self`, untracked |
| `derived(:name, equals: nil) { ... }` | reader over a lazy `Derived` | block runs with the instance as `self` |
| `effect { ... }` | an anonymous `Effect` started per instance | starts after `initialize` returns |

Instance API: `dispose` (disposes every effect this instance started; idempotent).

## Rules

- Write with an explicit receiver: `self.count += 1`. A bare `count = 1` is a local variable to the parser and leaves the signal untouched.
- Effects start after your own `initialize` has run, so they see the finished object once instead of running twice (defaults first, then a correction).
- Signals are per instance and created lazily on the first read or write; an attribute never touched never gets a signal.
- Subclasses inherit every declaration; readers and writers are plain methods, and inherited effects start alongside the subclass's own (blocks are gathered up the ancestor chain).
- Tracking does not stop at the class boundary. An effect outside the class that calls `counter.doubled` subscribes to it like any other read, which is how reactive objects compose.

## Choosing a default

| Form | Made when | Use for |
|---|---|---|
| positional `state :entries, []` | once, when the class body runs; shared by every instance | numbers, symbols, `nil`, frozen strings, `Data` values |
| block `state(:entries) { [] }` | once per instance, at first touch | arrays, hashes, any object you will change |

The block runs with the instance as `self`, so it can build from other attributes (`state(:seats) { Array.new(capacity) }`), and it runs untracked: an effect that first touches `seats` does not depend on `capacity`. A default is a starting value only; changing `capacity` later does not rebuild `seats`. Reach for `derived` when one attribute has to follow another.

Growing a collection is an assignment, in either form: `self.entries += ["x"]`, never `entries << "x"`. See `mutable-defaults.md`.

## Custom equality

`state :level, 1, equals: ->(prev, curr) { prev.abs == curr.abs }` and `derived(:name, equals: ...)` pass straight through to the signal. See `advanced-usage.md` for the three settings.

## Disposing an object's effects

- Effects that read only the instance's own attributes form a self-contained island that garbage collects with it: no call needed.
- Effects that read a signal outside the instance (a module-level `THEME = state("light")`) are held by that signal and keep running after your last reference is gone. Call `dispose` while you still hold the object.
- An instance created inside a running effect is adopted by it and disposed on that effect's re-run or disposal, so it needs no call either.

```ruby
panel = Panel.new        # effect reads THEME.value
THEME.value = "dark"     # panel's effect runs
panel.dispose
THEME.value = "light"    # nothing runs
```

See also: https://planetaska.github.io/hibiki/mutable-defaults/
Full docs: https://planetaska.github.io/hibiki/class-based-reactivity/
