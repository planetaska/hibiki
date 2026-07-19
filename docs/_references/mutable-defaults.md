---
title: Mutable state defaults
nav_order: 6
---

# Mutable state defaults

`Hibiki::Reactive`'s `state` macro accepts a default value in two forms:

```ruby
state :count, 0                 # positional default
state(:history) { [] }          # block default
```

They differ in **when the default is evaluated**, and for mutable values
(arrays, hashes, mutable strings, your own objects) that difference is a
correctness issue, not a style choice.

## The positional form is one shared object

A positional default is evaluated **once, when the class body runs** — the
macro captures that single object in a closure. Every instance's lazily
created signal is then initialized with a reference to *the same object*:

```ruby
class Feed
  include Hibiki::Reactive
  state :entries, []            # ONE array, shared by every Feed
end

a = Feed.new
b = Feed.new
a.entries << "hello"
b.entries                       # => ["hello"] — b sees a's data
```

This is the same trap as Rails attribute defaults (`attribute :tags,
default: []` shares one array across all records, which is why the Rails
idiom is `default: -> { [] }`), and the same reason `Hash.new([])` is a
classic Ruby footgun.

## In-place mutation also bypasses reactivity

The shared object is only half the problem. Mutating a value in place
(`<<`, `push`, `merge!`, `sub!`) never goes through the signal's writer, so
**no subscribers are notified** — deriveds stay cached and effects don't
run. Assigning the mutated object back doesn't help either:

```ruby
self.entries = entries << "hello"
```

`entries << "hello"` mutates the array and returns the *same object*, so
the write sees a value `==` to the current one and is discarded as a no-op
(writing an equal value never notifies — a core invariant). The mutation
happens; the graph never hears about it.

The correct update pattern for mutable state is to **assign a fresh
object**:

```ruby
self.entries += ["hello"]                  # new array
self.entries = entries.merge(key: value)   # new hash (Hash#merge, not merge!)
```

## The block form: fresh default per instance

```ruby
state(:history) { [] }
```

The block is stored at class-definition time but **called per instance**,
at the moment the signal is first touched. Each instance gets its own
fresh object. Two details of how it runs:

- It is `instance_exec`'d, so it can reference the instance's other
  attributes and methods.
- It runs **untracked**: the first touch may happen inside some effect's
  tracking window, and a default that reads other signals must not
  subscribe that outer observer.

## When the positional form is fine

Sharing an object nobody can mutate is harmless. Numbers, symbols, `nil`,
`true`/`false`, frozen strings (any literal under
`# frozen_string_literal: true`), and other frozen or immutable values are
all safe as positional defaults:

```ruby
state :count, 0                 # fine
state :label, "untitled"        # fine (frozen string literal)
state(:tags) { [] }             # block form — it's mutable
```

Rule of thumb: if the default is mutable, use the block form — and update
it by assigning a new object, never by mutating in place.
