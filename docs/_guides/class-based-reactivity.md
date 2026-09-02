---
title: Class-based reactivity
nav_order: 3
---

# Class-based reactivity

In [Getting started]({% link _guides/getting-started.md %}) every signal was a loose variable, and every read went through `.value`. That is fine for a script, but most Ruby lives in classes, and a class already has a place for its values: attributes. `Hibiki::Reactive` puts a signal behind each attribute. You declare them with class macros, read and write them like any other attribute, and the reactivity follows you around without a single `.value` in sight. Svelte 5 lets `$state`, `$derived`, and `$effect` live as class fields; this is the Ruby analogue.

Here is the counter again, this time as a class:

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

Look at the `derived` block: it says `count`, not `count.value`. That is a plain method call on the instance, and it is enough. The reader method fetches the signal's value, so the derived block registers its dependency the moment it calls `count`, exactly as it would have with `.value`. The same is true of the effect. Everything you learned about signals still applies here; only the spelling has changed.

## The three macros

Each macro is the class-level twin of a primitive you already know.

`state :name, default` defines a reader and a writer over a writable signal. Reading `count` tracks the dependency, and writing `self.count = 5` notifies everyone who read it. The default can also be given as a block, `state(:history) { [] }`, and the two forms differ in a way that matters; the section on defaults below explains it.

`derived(:name) { ... }` defines a reader over a computed signal. The block runs with the instance as `self`, so it can call the other attributes by name. It stays lazy: a write to `count` marks `doubled` stale, and the block runs again only when someone reads `doubled`.

`effect { ... }` registers a block to run when the object is created, and again whenever a value it read has changed. There is no name, because an effect is not a value you read; it is where the object does something.

One Ruby detail to keep in mind: a writer needs an explicit receiver. Inside a method, `count = 1` creates a local variable and leaves the signal untouched, which is why the example writes `self.count += 1`.

## When effects start

A class's effects start the moment an instance is created, after your own `initialize` has run. That order is deliberate. An effect usually reads state that the constructor sets up, and it should see the finished object, not the defaults:

```ruby
class Greeter
  include Hibiki::Reactive

  state :name, "world"
  effect { puts "hello, #{name}!" }

  def initialize(name)
    self.name = name
  end
end

greeter = Greeter.new("Ruby")  # prints "hello, Ruby!"
greeter.name = "Hibiki"        # prints "hello, Hibiki!"
```

The effect printed "hello, Ruby!" once, not "hello, world!" followed by a correction. Had it started before `initialize`, it would have run twice, and the first run would have been wrong.

## Every instance is its own island

The macros declare signals on the class, but the signals themselves belong to instances. Two counters share nothing:

```ruby
a = Counter.new  # prints "count is now 0"
b = Counter.new  # prints "count is now 0"

a.increment      # prints "count is now 1"
b.count          # => 0
```

Each signal is created lazily, on the first read or write of its attribute; an attribute that is never touched never gets a signal at all. Subclasses inherit every declaration: the readers and writers are ordinary methods, so they come along with the rest of the class, and inherited effects start alongside the subclass's own. A `class FancyCounter < Counter` gets `count`, `doubled`, and the printing effect for free.

## Reading from the outside

So far every read has happened inside the class, in its own derived and effect blocks. Does the tracking stop at the class boundary? It does not. Hibiki records a dependency whenever a signal is read, and it does not care where the reader is. Code outside the class that calls `counter.doubled` is reading a signal too, so an effect written out there subscribes to the counter just as one inside the class would:

```ruby
counter = Counter.new
effect { puts "someone else sees #{counter.doubled}" }  # prints "someone else sees 0"

counter.increment  # prints "count is now 1", then "someone else sees 2"
```

This is what lets reactive objects compose. A view can read a model's attributes, a model can read another model's, and the graph knits itself together from ordinary method calls, exactly as it did with loose signals.

## Choosing a default

`state` takes its default in two forms, and the choice is about *when* the default is made. A positional default is made once, when the class body runs. For a number, a symbol, or a frozen string that is all you need. For an array, a hash, or any object you intend to change, take care, because that one object is the default for every instance:

```ruby
class Feed
  include Hibiki::Reactive

  state :entries, []   # one array, made when the class body runs
end

a = Feed.new
b = Feed.new
a.entries << "hello"
b.entries            # => ["hello"]  b sees a's entry
```

Both feeds were handed the same array, so what one of them changes, the other sees. The block form runs once per instance instead, at the first touch of the attribute, and hands each instance a fresh object of its own:

```ruby
class Feed
  include Hibiki::Reactive

  state(:entries) { [] }   # a new array for every Feed
end

a = Feed.new
b = Feed.new
a.entries << "hello"
b.entries                # => []
```

The rule is short: a default you will change goes in a block. Rails has the same trap in attribute defaults, and the same cure.

The `<<` in these examples hides a second problem, separate from the sharing. It changes the array in place, and an in-place change never goes through the signal's writer, so no signal is written and nothing that read `entries` hears about it. A derived stays cached and an effect stays quiet, in the block form just as in the positional one, because Hibiki notices assignments and nothing else. The correct way to grow a collection is to assign a new one:

```ruby
a.entries += ["hello"]   # Correct: a new array, written through the signal
a.entries << "hello"     # Wrong: the same array, changed in place, and nobody is told
```

The Feed examples gave one reason to reach for the block form: a fresh object for every instance. It is not the only thing the block offers. The block runs with the instance as `self`, so it can build the default from other attributes:

```ruby
class Roster
  include Hibiki::Reactive

  state :capacity, 3
  state(:seats) { Array.new(capacity) }   # a default built from another attribute
end

roster = Roster.new
effect { puts "#{roster.seats.size} seats" }   # prints "3 seats"

roster.capacity = 5                            # prints nothing
roster.seats = roster.seats + [nil]            # prints "4 seats"
```

Two things happened here that are worth a closer look. The effect was the first to touch `seats`, so the default block ran inside the effect, and the block read `capacity`. Yet when `capacity` changed, the effect stayed quiet. That is because a default block runs untracked: the reads it makes are not recorded, so the effect depends on `seats` alone, exactly as it appears to. And a default is only a starting value. Changing `capacity` later does not rebuild `seats`, because that would make it a derived, and a derived is what you should reach for when one attribute has to follow another.

The [Mutable state defaults reference]({% link _references/mutable-defaults.md %}) walks through both failure modes in detail and shows the update patterns that work for arrays, hashes, and objects of your own.

## Custom equality

Both `state` and `derived` accept `equals:`, and pass it straight through to the signal underneath. Use it when `==` is the wrong test for a change:

```ruby
state :level, 1, equals: ->(prev, curr) { prev.abs == curr.abs }
```

Everything on [Custom equality]({% link _guides/advanced-usage.md %}#custom-equality-equals) applies here without change.

## Disposing an object's effects

Effects declared with the macro live as long as the object, and most of the time that is what you want. An object whose effects read only its own attributes needs no cleanup: when the object is garbage collected, its effects go with it. Every `Counter` on this page is such an object.

An object whose effects read a signal *outside* itself is different. The outside signal holds a reference to the effect, and the effect keeps running as long as the signal lives. Here a panel reads a theme that belongs to the whole application:

```ruby
THEME = state("light")

class Panel
  include Hibiki::Reactive

  state :title, "Settings"
  effect { puts "#{title} drawn in #{THEME.value} mode" }
end

panel = Panel.new        # prints "Settings drawn in light mode"
THEME.value = "dark"     # prints "Settings drawn in dark mode"

panel.dispose
THEME.value = "light"    # prints nothing
```

Call `dispose` when you are done with such an object. Its effects stop, and calling it a second time does nothing. Without the call, the effect outlives your last reference to the object:

```ruby
panel = Panel.new        # prints "Settings drawn in light mode"
panel = nil
THEME.value = "dark"     # prints "Settings drawn in dark mode"
```

`THEME` still refers to the panel's effect, so the panel draws at every change of theme for the rest of the program, and nothing can reach it to stop it. Dispose the object while you still hold it.

On the other hand, an object created inside a running effect never needs you to call `dispose`. The outer effect adopts it, and disposes it whenever the outer effect re-runs or is itself disposed, like any other child:

```ruby
page = state("home")

effect do
  puts "showing #{page.value}"
  Panel.new              # a new panel on every run; prints "Settings drawn in light mode"
end

page.value = "about"     # prints "showing about", then "Settings drawn in light mode"
THEME.value = "dark"     # prints "Settings drawn in dark mode" once
```

The effect ran twice and created a panel each time. When `page` changed, the re-run disposed the first panel before creating the second, so only the second panel is listening when the theme changes. The [Lifecycle reference]({% link _references/lifecycle-in-detail.md %}) describes the owner tree behind this.

## Where to next

- [Advanced usage]({% link _guides/advanced-usage.md %}) covers untracked reads, batching, and the lifecycle of long-lived effects, all of which work the same way inside a class.
- [Why no transparent signals?]({% link _references/why-no-transparent-signals.md %}) explains why a class is the right home for attribute-style access, and why Hibiki stops there.
