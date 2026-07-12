# Why no transparent signals?

Two designs were evaluated and rejected during Hibiki's development. Both are
attempts to make signals look like plain Ruby values — no `.value` anywhere.
Each one hits a hard wall in the Ruby language itself, not a design-taste
issue, which is why they are documented here rather than left open for
relitigating.

## 1. Transparent value wrappers

**The idea:** make a signal object *pretend to be* its value by forwarding
every method call to `.value` via `method_missing`:

```ruby
count = Hibiki::State.new(5)
count + 1        # method_missing forwards :+ to count.value → 6, and
                 # the read registers a dependency. Looks great!
count.to_s       # "5" — also great
```

**Why it breaks:** Ruby's truthiness is not a method. There is no `to_bool`
hook — `if x` is falsy *only* when `x` is the actual objects `nil` or
`false`. A wrapper is neither, so it is **always truthy**, and
`method_missing` never even fires:

```ruby
flag = Hibiki::State.new(false)   # transparent wrapper holding false

if flag                            # wrapper object itself → ALWAYS truthy
  do_the_thing                     # runs even though the value is false!
end
```

No error, no warning — it just silently takes the wrong branch. And the
cruelest part is *which* feature this poisons: conditionals are exactly where
fine-grained reactivity earns its keep. Dynamic dependency tracking (the
`flag ? a : b` pattern, one of Hibiki's core invariants) exists so an effect
subscribes to `a` only while `flag` is true. If `if flag` is broken, the
flagship use case is broken.

The lie spreads beyond `if`:

```ruby
name = Hibiki::State.new(nil)
name.nil?          # you can forward this one... but:
name == nil        # depends on forwarding, while
nil == name        # calls NilClass#==, which you can't touch → false. Inconsistent.
name.equal?(nil)   # false — identity can't be forwarded
case name when String then ... end   # String#=== on the wrapper → false even if value is a String
```

This is why Solid uses getter *functions* (`count()`) and Svelte 5 gets
transparency only via a **compiler** that rewrites `count` into
`$.get(count)` at build time. Ruby has no compile step, so runtime magic is
the only route — and truthiness slams that door.

## 2. The `reactive do ... end` block DSL

**The idea:** a Svelte-file-like block where bare local variables are
reactive:

```ruby
reactive do
  count = 0             # wish: creates a signal
  doubled = count * 2   # wish: creates a derived
  count = 1             # wish: reactive write, notifies doubled
end
```

**Why it breaks:** in Ruby, `count = 1` is decided by the **parser**, not at
runtime. The moment an assignment to a bare name appears, that name is a
local variable for the rest of the scope — no method call happens, so there
is no `method_missing`, no hook, nothing for a library to intercept. The
write is invisible to Hibiki. (Bare *reads* of an undefined name would
dispatch as method calls and could be caught, but reads alone are useless if
writes can't be.)

The only escape is to force writes through a receiver:

```ruby
reactive do
  self.count = 1   # now it's a method call — interceptable
end
```

…but once every write is `self.count =`, the "bare locals" illusion is dead
and you are really just writing methods on an object. And Ruby already has a
first-class, inheritable, testable construct for "an object with reactive
attribute methods" — a class. That's `Hibiki::Reactive`:

```ruby
class Counter
  include Hibiki::Reactive

  state :count, 0
  derived(:doubled) { count * 2 }
  effect { puts "count is now #{count}" }

  def increment = self.count += 1
end
```

Same ergonomic payoff the block DSL was chasing — no `.value` at usage
sites, dependency tracking flows through plain method calls — but built on
ordinary `define_method` readers/writers, so `if flag` works (the reader
returns the real value, not a wrapper), inheritance works, and nothing lies.

## The one-line summary

Transparency at *usage sites* is achievable and Hibiki has it (the
`Hibiki::Reactive` macros). Transparency of *the value object itself* and of
*bare local assignment* are both impossible in Ruby without a compiler, and
faking them produces silent wrong-branch bugs — hence: rejected, don't
relitigate.
