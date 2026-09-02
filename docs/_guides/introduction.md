---
title: Introduction
nav_order: 1
---

# Introduction

Hibiki (響き, "echo, resonance") brings signals, the reactive primitive behind Svelte 5, to Ruby.

A signal is a value that remembers who read it. Wrap a value in a signal, read it inside a computation, and that computation stays in step with the value from then on. Hibiki offers three small primitives for this: `state` holds a value, `derived` computes a new value from other signals, and `effect` runs a block right away and runs it again whenever a value it read changes. You write ordinary Ruby, and the bookkeeping happens on its own.

Here is an example of reactive Ruby: a running total that keeps itself up to date.

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

Can you see the magic here? `total` reads `price` and `quantity`, so it depends on both. The effect reads `total`, so it depends on `total`. Neither relationship appears in the code as a declaration. Hibiki noticed each read as it happened and recorded it, so the dependency graph *assembled itself* from plain method calls. When `quantity` changes, the change ripples out to `total` and on to the effect, which prints the new total.

Because Hibiki watches reads rather than declarations, the graph is free to change shape as your program runs. A block such as `flag.value ? a.value : b.value` depends on `a` while the flag is true and switches to `b` once the flag turns false, with the dependencies re-collected on every run. Hibiki is also frugal about work: a `derived` waits to recompute until someone reads it, and a write that leaves a value unchanged is quietly skipped, so downstream work happens only for a real change.

Hibiki is pure Ruby. It depends on the standard library alone, and it works by observing method calls rather than rewriting the AST, leaving the code exactly as you wrote it. Head to [Getting started]({{ "/getting-started/" | relative_url }}) to install it and build your first reactive Ruby program.
