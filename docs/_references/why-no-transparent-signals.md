---
title: Why no transparent signals?
nav_order: 3
---

# Why no transparent signals?

Every read of a signal in these docs goes through `.value`. After you have typed `count.value + 1` a few dozen times, a question suggests itself: could Hibiki hide that? Could `count` simply *be* 5, and still remember who read it? Two designs were tried during Hibiki's development, and both were rejected. Not because of taste: each ran into a rule of the Ruby language that no library can bend, and each fails in the worst possible way, silently, by taking the wrong branch. This page walks through both, so that the question has a settled answer, and so that you can see why `Hibiki::Reactive` takes the shape it does.

## A signal that pretends to be its value

The first idea is a wrapper that forwards every method call to the value inside. Ruby makes such a thing easy to sketch. Inherit from `BasicObject`, which has almost no methods of its own, and let `method_missing` pass everything through:

```ruby
class Transparent < BasicObject
  def initialize(signal) = @signal = signal

  def method_missing(name, *args, &) = @signal.value.__send__(name, *args, &)
  def respond_to_missing?(name, include_private = false) = @signal.value.respond_to?(name, include_private)
end
```

Every forwarded call reads `@signal.value`, so every use of the wrapper registers a dependency, and the first tests look wonderful:

```ruby
count  = state(5)
number = Transparent.new(count)

number + 1                            # => 6
number.to_s                           # => "5"
effect { puts "count is #{number}" }  # prints "count is 5"
count.value = 6                       # prints "count is 6"
```

Every read went through the wrapper without a `.value`, and the effect still re-ran when the signal changed underneath it. Then you write the first `if`:

```ruby
flag = Transparent.new(state(false))

if flag
  puts "on"   # prints "on", though the value is false
end
```

Truthiness in Ruby is not a method. There is no `to_bool` hook to forward. An `if` asks one question only: is this object `nil` or `false`? A wrapper is neither. It is always truthy, `method_missing` never runs, and the wrong branch executes with no error and no warning.

The cruel part is which feature this poisons. Conditionals are where fine-grained reactivity earns its keep. An effect that reads `flag ? a : b` subscribes to `a` only while the flag is true and switches to `b` once it flips, as [Lifecycle in detail]({% link _references/lifecycle-in-detail.md %}#what-a-re-run-tears-down) shows. A wrapper breaks exactly that example.

The cracks spread beyond `if`. Ruby answers `equal?` and `==` on `BasicObject` itself, before `method_missing` gets a look in, and `case` asks the class rather than the object:

```ruby
name = Transparent.new(state(nil))

name.nil?         # => true, forwarded
name == nil       # => false, unless the wrapper forwards == by hand
nil == name       # => false either way: NilClass#== answers, and you cannot change it
name.equal?(nil)  # => false: identity cannot be forwarded

title = Transparent.new(state("Hibiki"))

case title
when String then "a string"   # String === title asks the wrapper's class
else "not a string"           # => "not a string"
end
```

Svelte 5 does have transparent signals, and it is worth seeing how. A Svelte component reads `count` as a bare name, and the *compiler* rewrites that read into `$.get(count)` before the code ever runs. The transparency lives in a build step. Ruby has no build step, so runtime tricks are the only route to it, and truthiness closes that route.

## Bare variables in a reactive block

The second idea skips the wrapper and reaches for a block, in the spirit of a Svelte file. Inside the block, an ordinary local variable would be a signal:

```ruby
reactive do
  count = 0             # wish: creates a state
  doubled = count * 2   # wish: creates a derived
  count = 1             # wish: a reactive write, and doubled updates
end
```

This time the wall is the parser. The moment Ruby sees `count = 0`, it marks `count` as a local variable for the rest of the block. From that line on, a bare `count` is a variable lookup, not a method call. No method call means no `method_missing`, no hook, and nothing for a library to intercept. A small probe shows the switch happening:

```ruby
class Probe
  def method_missing(name, *) = puts "intercepted #{name}"
  def respond_to_missing?(*) = true

  def run
    count           # prints "intercepted count": no local yet, so a method call
    count = 1       # prints nothing: the parser made count a local
    count           # prints nothing: a local read
    self.count = 2  # prints "intercepted count=": a receiver makes it a call
  end
end
```

The read on the first line can be caught, but reads alone are useless while the writes stay invisible. The only escape is the last line: give every write an explicit receiver.

```ruby
reactive do
  self.count = 1   # a method call, so it can be intercepted
end
```

Once every write is `self.count =`, the illusion of bare locals is gone, and what remains is an object with reactive attribute methods. Ruby already has a first-class, inheritable, testable construct for exactly that: a class. So that is what Hibiki ships.

```ruby
class Counter
  include Hibiki::Reactive

  state :count, 0
  derived(:doubled) { count * 2 }
  effect { puts "count is now #{count}" }

  def increment = self.count += 1
end
```

This has the payoff the block was chasing. No `.value` at the point of use, and dependency tracking flows through plain method calls. It has none of the traps, because the readers and writers are ordinary methods defined with `define_method`. `count` returns the real Integer rather than a wrapper, so `if` works, `==` works, `case` works, and inheritance comes for free. [Class-based reactivity]({% link _guides/class-based-reactivity.md %}) shows this in full.

## TL;DR

- Transparency at the **point of use** is achievable, and Hibiki has it in `Hibiki::Reactive`.
- Transparency of the **value object** fails on truthiness: `if wrapper` is always true.
- Transparency of **bare assignment** fails on the parser: `count = 1` is never a method call.
- Both failures are silent wrong-branch bugs, so both designs are rejected.
