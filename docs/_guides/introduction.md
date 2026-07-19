---
title: Introduction
nav_order: 1
---

# Introduction

Hibiki (hi-bi-ki; [çi.bi.ki]) (響き, "echo, resonance") brings Svelte-5-style signals to Ruby: three small primitives — `state`, `derived`, `effect` — that track their own dependencies at runtime. You never wire an observer or declare what depends on what; any signal read while a computation runs subscribes it, automatically.

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

Can you see the magic? Here, I didn't tell `total` to watch `price` and `quantity`, and nobody told the effect to watch `total` — the dependency graph *assembled itself* from plain Ruby reads, and updates flow through it the moment anything changes. Writing an equal value is a no-op, deriveds recompute lazily and only when stale, and dependencies are re-collected on every run, so even conditional reads (`flag ? a.value : b.value`) track correctly.

No runtime dependencies, no magic AST rewriting — just Ruby. Head to [Getting started]({{ "/getting-started/" | relative_url }}) to install it and build something.
