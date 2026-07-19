---
title: Getting started
nav_order: 2
---

# Getting started

Hibiki has no runtime dependencies and requires Ruby >= 3.4.

## Installation

```ruby
# Gemfile
gem "hibiki"
```

Or install it directly:

```sh
gem install hibiki
```

## Two flavors

The DSL gives you bare `state` / `derived` / `effect` helpers. It is strictly opt-in:

```ruby
require "hibiki"
include Hibiki::DSL

x = state(0)
y = derived { x.value + 1 }

x.value = 10
y.value # => 11
```

Prefer no DSL? We get you. Use the classes directly:

```ruby
require "hibiki"

x = Hibiki::State.new(0)
y = Hibiki::Derived.new { x.value + 1 }

x.value = 10
y.value # => 11
```

## The three primitives

**`state(v)`** — a writable signal. Reading `.value` registers a dependency; writing notifies subscribers. Writing an `==`-equal value is a no-op.

```ruby
counter = state(0)
counter.value += 1
counter.update { it + 1 } # Ruby's in-place sugar
```

**`derived { }`** — a lazy computed signal. It recomputes on read when marked dirty (when any state it depends on changes), never on write, and caches its value until a dependency changes.

```ruby
doubled = derived { counter.value * 2 }
doubled.value # => 4
```

**`effect { }`** — an eager side effect. It *runs immediately* and re-runs whenever a dependency (any state inside the effect block) changes.

```ruby
name = state("world")
effect { puts "hello, #{name.value}!" } # prints "hello, world!"

name.value = "Ruby"                     # prints "hello, Ruby!"
```
