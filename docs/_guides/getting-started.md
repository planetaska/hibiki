---
title: Getting started
nav_order: 2
---

# Getting started

This page installs Hibiki and introduces its three primitives one at a time, until you can write a small reactive program of your own. Hibiki is a single gem with no runtime dependencies, and it runs on Ruby 3.4 or later.

## Installation

Add it to your Gemfile:

```ruby
gem "hibiki"
```

Or install it directly:

```sh
gem install hibiki
```

## Two flavors

Hibiki ships with an optional DSL: a handful of bare helpers named `state`, `derived`, and `effect`. Include it, and your reactive code reads like the examples in these docs:

```ruby
require "hibiki"
include Hibiki::DSL

x = state(0)
y = derived { x.value + 1 }

x.value = 10
y.value # => 11
```

The DSL is strictly opt-in. Requiring the gem never includes it for you, so a library built on Hibiki adds nothing to its callers' namespace. Prefer to skip it? Use the classes directly. They are the same objects; the helpers are only shorter names for `new`:

```ruby
require "hibiki"

x = Hibiki::State.new(0)
y = Hibiki::Derived.new { x.value + 1 }

x.value = 10
y.value # => 11
```

The two styles mix freely. The rest of this page uses the DSL.

## The three primitives

Everything in Hibiki is built from three parts. A **state** holds a value you can change. A **derived** computes a value from other signals. An **effect** runs a block, and runs it again whenever something the block read has changed. The first two are signals: values that remember who read them. The third is where something actually happens.

### `state`: a value that remembers who read it

`state(v)` wraps a value in a writable signal. Read it through `.value`, and the reader is quietly noted down. Write to it, and everyone who read it hears about the change.

```ruby
counter = state(0)
counter.value += 1
counter.update { it + 1 } # the same write, as a block
```

Writing a value *equal* to the one already held is a no-op: nothing that read it is notified, and nothing downstream runs. Here equal means `==` unless you say otherwise: [Custom equality]({% link _guides/advanced-usage.md %}#custom-equality-equals) shows how to supply your own comparison per signal.

### `derived`: a value that computes itself

`derived { }` turns a block into a read-only signal. Whatever the block reads becomes a dependency, and the result is cached until one of those dependencies changes.

```ruby
doubled = derived { counter.value * 2 }
doubled.value # => 4
```

A derived is lazy. When `counter` changes, `doubled` does not recompute on the spot; it only marks itself stale. The block runs again the next time someone reads `doubled.value`, and never runs if nobody reads it. You can chain deriveds as deep as you like, and each one does its work only when a reader asks for it.

### `effect`: a block that keeps itself current

`effect { }` runs its block immediately. Every signal the block reads on that run becomes a dependency, and whenever one of them changes, the block runs again.

```ruby
name = state("world")
effect { puts "hello, #{name.value}!" } # prints "hello, world!"

name.value = "Ruby"                     # prints "hello, Ruby!"
```

An effect is where reactivity meets the outside world: printing a line, writing to a socket, updating a screen. A state and a derived are only values, and the effect is what acts on them. Like a state, an effect ignores a change that changes nothing: it runs again only when a value it read is actually different from last time.

## Putting it together

Here is a to-do list that counts its own remaining items. The state holds the list, the derived counts it, and the effect reports the count.

```ruby
todos     = state([])
remaining = derived { todos.value.count { !it[:done] } }

effect { puts "#{remaining.value} left to do" }             # prints "0 left to do"

todos.value += [{ title: "Read the docs", done: false }]    # prints "1 left to do"
todos.value += [{ title: "Write some Ruby", done: false }]  # prints "2 left to do"
todos.value = todos.value.map { it.merge(done: true) }      # prints "0 left to do"
```

Notice that every step assigns a new array instead of pushing onto the old one. Hibiki sees assignments and nothing else. A `todos.value << item` would change the array in place, and no signal would hear about it, so the count would stay where it was. When a signal holds an array or a hash, build the new value and assign it.

## Where to next

- [Class-based reactivity]({% link _guides/class-based-reactivity.md %}) declares signals as class macros, so you can drop the `.value` and use them as plain attributes.
- [Advanced usage]({% link _guides/advanced-usage.md %}) covers untracked reads, batching, custom equality, and the lifecycle of long-lived effects.
