# === Non-reactive Ruby behavior
x = 0
y = x + 1
x += 1
puts "=== Non-reactive Ruby ==="
puts y

# === Reactivity demo
require_relative "lib/hibiki"
include Hibiki::DSL # the gem is opt-in; a demo script including into main is fine

puts "=== Reactive Ruby ==="

# --- Original example, adapted to legal Ruby -------------------------
x = state(0)
y = derived { x.value + 1 }

x.value += 1
puts y            # => 2  (Derived#to_s reads .value)

# --- chained deriveds ------------------------------------------------------
doubled = derived { y.value * 2 }
puts doubled      # => 4

x.value = 10
puts y            # => 11
puts doubled      # => 22

# --- effects (Svelte's $effect) --------------------------------------------
name = state("world")
effect { puts "hello, #{name.value}!" }   # runs immediately: hello, world!
name.value = "Aska"                        # re-runs: hello, Aska!

# --- dynamic dependencies: the thing static analysis can't do --------------
flag = state(true)
a = state("A")
b = state("B")
picked = derived { flag.value ? a.value : b.value }

puts picked       # => A
b.value = "B2"    # picked does NOT depend on b right now...
puts picked       # => A (no recompute needed)
flag.value = false
puts picked       # => B2 (deps re-collected on recompute)