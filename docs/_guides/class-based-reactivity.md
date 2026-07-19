---
title: Class-based reactivity
nav_order: 3
---

# Class-based reactivity

Svelte 5 allows `$state` / `$derived` / `$effect` as class fields; `Hibiki::Reactive` is the Ruby analogue. Declare signals with class macros and use them as plain attributes — no more `.value` in code:

```ruby
class Counter
  include Hibiki::Reactive

  state :count, 0
  state(:history) { [] }          # block form: fresh default per instance
  derived(:doubled) { count * 2 }
  effect { puts "count is now #{count}" } # starts on Counter.new

  def increment = self.count += 1
end

counter = Counter.new  # prints "count is now 0"
counter.increment      # prints "count is now 1"
counter.doubled        # => 2
```

Signals are per-instance and created lazily; subclasses inherit all declarations. Use the block form for mutable defaults (a positional default is one shared object, the same gotcha as Rails attribute defaults).