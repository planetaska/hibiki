---
title: Mutable state defaults
nav_order: 4
---

# Mutable state defaults

The `state` macro in `Hibiki::Reactive` takes its default value in one of two forms:

```ruby
state :count, 0          # a positional default
state(:history) { [] }   # a block default
```

Both give a new instance a starting value. They differ in *when that value is made*. The positional form makes it once, when Ruby reads the class body. The block form makes it once per instance, the first time that instance touches the attribute. For a number the difference is invisible. For an array, a hash, or an object of your own, it decides whether your program is correct. This page shows what goes wrong, why, and how to update a collection so the graph hears about it. The [class-based reactivity guide]({% link _guides/class-based-reactivity.md %}#choosing-a-default) has the short version.

## A positional default is one shared object

Ruby runs a class body once. When it reaches `state :entries, []`, it builds one array and hands it to the macro, and the macro keeps it. Every instance's signal is later created with a reference to that same array. Here is an example that mistakenly makes two feeds share one array:

```ruby
class Feed
  include Hibiki::Reactive
  state :entries, []   # one array, kept by the class
end

a = Feed.new
b = Feed.new
a.entries << "hello"
b.entries            # => ["hello"]
```

The second feed never added anything, yet it has an entry. Both attributes point at the array the class body made. This is the same trap as `attribute :tags, default: []` in Rails, which shares one array across every record, and the same reason `Hash.new([])` is a [classic Ruby mistake](https://bugs.ruby-lang.org/issues/19063). All three have the same cure: build the value later, once per owner.

## Changing a value in place is not a write

Sharing is only half of the trouble with `a.entries << "hello"`. The other half is that nothing reactive happened. Hibiki notices assignments and nothing else. A method like `<<`, `push`, `merge!`, or `sub!` changes the object inside the signal, and the signal never learns of it. A derived that read the old contents keeps its cached answer, and an effect stays quiet:

```ruby
class Cart
  include Hibiki::Reactive
  state(:prices) { {} }
  derived(:total) { prices.values.sum }
  effect { puts "total is #{total}" }
end

cart = Cart.new             # prints "total is 0"
cart.prices[:apple] = 3     # prints nothing
cart.total                  # => 0, and the hash holds an apple
```

The natural repair is to assign the changed object back. That does not work either, and the reason is worth knowing:

```ruby
cart.prices = cart.prices.merge!(pear: 5)   # prints nothing
```

`merge!` changes the hash and returns *the same hash*. The writer compares the incoming value with the current one, finds them equal, and drops the write, because writing an equal value never notifies. That is a [core rule]({% link _guides/getting-started.md %}#the-three-primitives) of the library, and the writer cannot tell the difference between "the same object, unchanged" and "the same object, changed underneath". The change happened. The graph never heard about it.

## Update by assigning a fresh object

The fix follows from the rule. Give the writer a new object, and the comparison finds a difference:

```ruby
cart.prices = cart.prices.merge(fig: 1)   # prints "total is 9": a new hash, and the graph sees everything at last
```

Every destructive method has a counterpart that returns a copy. Here are the ones you will meet most often, each beside the method to use instead:

```ruby
self.entries += ["hello"]                  # Array: + builds a new array, << does not
self.entries  = entries.reject(&:done?)    # reject, not reject!
self.prices   = prices.merge(pear: 5)      # Hash: merge, not merge!
self.title    = title.sub("a", "b")        # String: sub, not sub!
```

For objects of your own, the cleanest state is a value object that produces changed copies. `Data#with` does exactly that:

```ruby
Point = Data.define(:x, :y)

class Canvas
  include Hibiki::Reactive
  state :origin, Point.new(x: 0, y: 0)     # immutable, so sharing is fine
  effect { puts "origin at #{origin.x},#{origin.y}" }
end

canvas = Canvas.new                        # prints "origin at 0,0"
canvas.origin = canvas.origin.with(x: 4)   # prints "origin at 4,0"
```

Sometimes a copy is the wrong price to pay: a large buffer, or an object that must keep its identity. For those, tell the signal to stop comparing. `equals: false` makes every write notify, so changing in place and then assigning the object back to itself becomes a real update:

```ruby
class Doc
  include Hibiki::Reactive
  state(:body, equals: false) { +"" }
  effect { puts "body is #{body.inspect}" }
end

doc = Doc.new       # prints 'body is ""'
doc.body << "hi"    # prints nothing: still a change in place
doc.body = doc.body # prints 'body is "hi"'
```

The assignment is now the moment you tell the graph "look again". [Custom equality]({% link _guides/class-based-reactivity.md %}#custom-equality) covers the rest of what `equals:` accepts.

## The block form makes a fresh default per instance

```ruby
state(:history) { [] }
```

The macro stores the block at class-definition time and calls it later, once for each instance, the first time that instance reads or writes the attribute. Each instance gets an array nobody else holds. The block runs under two rules:

- **The instance is `self`.** A default can be built from the instance's other attributes and methods.
- **Its reads are not tracked.** The first touch often happens inside an effect, and a default that reads another signal must not make that effect depend on it. The default is a starting value, not a derived.

The guide's [Roster example]({% link _guides/class-based-reactivity.md %}#choosing-a-default) shows both rules at work.

## When the positional form is fine

The danger in sharing was never the sharing itself. It was that one instance could change the shared object and every other instance would see the change. An object that cannot be changed removes that danger. Suppose two counters start from the same value `0`:

```ruby
class Counter
  include Hibiki::Reactive
  state :count, 0   # one Integer, shared by every Counter
end

a = Counter.new
b = Counter.new
a.count += 1
a.count           # => 1
b.count           # => 0
```

Both counters began holding the same object, yet `b` was untouched. An Integer has no method that alters it in place. The only way from 0 to 1 is `+`, which returns a different object, and `a.count += 1` assigns that new object through the writer into `a`'s own signal. The shared `0` is still `0`, and `b` still holds it. Sharing an object that cannot change is the same as giving each instance its own copy, because nothing done to one reference can reach the others.

Compare the array from the top of the page. `a.entries << "hello"` has an in-place path, so the shared object itself changed, and `b` saw it. That is the whole difference. The values that are safe to share are the ones with no such path:

- **Numbers, symbols, `nil`, `true`, and `false`** have no methods that alter them.
- **Frozen strings** raise `FrozenError` on `<<`, `sub!`, and every other in-place method. A string literal is frozen when its file starts with `# frozen_string_literal: true`.
- **`Data` values** have no setters, and `with` returns a copy.

```ruby
# frozen_string_literal: true

state :count, 0                           # fine
state :label, "untitled"                  # fine: the comment above freezes it
state :origin, Point.new(x: 0, y: 0)      # fine: a Data value cannot change
state(:tags) { [] }                       # block form: an array can
```

There is a symmetry here worth noticing. The update rule for mutable state is "assign a fresh object, never change in place". An immutable value enforces that rule for you, because changing it in place is impossible. That is why it needs no block.

Rule of thumb:

- If the default can change, make it in a block.
- To update it, assign a new object. Never update state in place.
