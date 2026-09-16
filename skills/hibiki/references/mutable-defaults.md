# Mutable state defaults

`state` in `Hibiki::Reactive` takes its default two ways, and they differ in when the value is made:

| Form | Made | Consequence |
|---|---|---|
| `state :entries, []` | once, when Ruby reads the class body | one object shared by every instance |
| `state(:entries) { [] }` | once per instance, at the first read or write | a fresh object per instance; the block runs as the instance, untracked |

For a number the difference is invisible. For an array, a hash, or an object of your own it decides whether the program is correct: `a.entries << "x"` on a positional default shows up in `b.entries`. Same trap as Rails's `attribute :tags, default: []` and `Hash.new([])`.

## Two separate failures in `entries << "x"`

1. Sharing (positional form only): every instance points at the class body's array.
2. Silence (both forms): `<<`, `push`, `merge!`, `sub!` change the object inside the signal without a write, so a derived keeps its cached answer and an effect stays quiet.

Assigning the changed object back does not help either: `self.prices = prices.merge!(pear: 5)` hands the writer the same object, `==` finds it equal, and the write is dropped. The writer cannot tell "same object, unchanged" from "same object, changed underneath".

## Update by assigning a fresh object

| Instead of | Write |
|---|---|
| `entries << x`, `push` | `self.entries += [x]` |
| `entries.reject!` | `self.entries = entries.reject(&:done?)` |
| `prices.merge!(k: v)`, `prices[k] = v` | `self.prices = prices.merge(k: v)` |
| `title.sub!` | `self.title = title.sub("a", "b")` |
| a setter on your own object | a `Data` value and `self.origin = origin.with(x: 4)` |

```ruby
Point = Data.define(:x, :y)

class Canvas
  include Hibiki::Reactive
  state :origin, Point.new(x: 0, y: 0)     # immutable, so a positional default is fine
  effect { puts "origin at #{origin.x},#{origin.y}" }
end
canvas.origin = canvas.origin.with(x: 4)   # prints "origin at 4,0"
```

When a copy is the wrong price (a large buffer, an object that must keep its identity), stop comparing with `equals: false`: change in place, then assign the object back to itself to say "look again".

```ruby
state(:body, equals: false) { +"" }
doc.body << "hi"    # still silent
doc.body = doc.body # now notifies
```

## When the positional form is fine

Values with no in-place path are safe to share: numbers, symbols, `nil`, `true`, `false`, frozen strings (a literal under `# frozen_string_literal: true`), and `Data` values. `a.count += 1` assigns a new Integer through `a`'s own writer, so `b` is untouched.

Rule of thumb: a default that can change goes in a block; to update it, assign a new object, never change state in place.

See also: https://planetaska.github.io/hibiki/class-based-reactivity/
Full docs: https://planetaska.github.io/hibiki/mutable-defaults/
