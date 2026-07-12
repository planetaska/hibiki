# frozen_string_literal: true

# === Sample Ruby code
puts "=== Consider sample Ruby code:"
puts "x = 0"
puts "y = x + 1"
puts "x += 1"
puts "puts y"

puts "\n>>> What is y now?"

# === Non-reactive Ruby behavior
x = 0
y = x + 1
x += 1 # rubocop:disable Lint/UselessAssignment -- the whole point: y will NOT update
puts "\n=== Non-reactive Ruby ==="
puts y

# === Reactivity demo
require_relative "lib/hibiki"
include Hibiki::DSL # the gem is opt-in; a demo script including into main is fine

puts "\n=== Reactive Ruby ==="

# --- Original example, adapted to legal Ruby -------------------------
x = state(0)
y = derived { x.value + 1 }

x.value += 1
puts y # => 2  (Derived#to_s reads .value)

puts "\n=== Doubled y through derived ==="

# --- chained deriveds ------------------------------------------------------
doubled = derived { y.value * 2 }
puts doubled      # => 4

x.value = 10
puts y            # => 11
puts doubled      # => 22

puts "\n=== Effects ==="

# --- effects (Svelte's $effect) --------------------------------------------
name = state("world")
effect { puts "hello, #{name.value}!" } # runs immediately: hello, world!
name.value = "Hibiki" # re-runs: hello, Hibiki!

puts "\n=== Dynamic dependencies ==="

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

puts "\n=== Batching ==="

# --- batching: many writes, one effect run ----------------------------------
first = state("Alan")
last = state("Turing")
effect { puts "full name: #{first.value} #{last.value}" } # runs immediately

# the effect runs ONCE at batch exit, seeing both new values —
# never an inconsistent "Yukihiro Turing"
batch do
  first.value = "Yukihiro"
  last.value = "Matsumoto"
end

puts "\n=== Class-based reactivity ==="

# --- Hibiki::Reactive: Svelte 5 class fields, Ruby style --------------------
# No .value anywhere: readers/writers are plain methods over per-instance
# signals, and the class-level effect starts when the instance is created.
class Counter
  include Hibiki::Reactive

  state :count, 0
  derived(:doubled) { count * 2 }
  effect { puts "count=#{count} doubled=#{doubled}" } # runs on Counter.new

  def increment = self.count += 1
end

counter = Counter.new # => count=0 doubled=0
counter.increment     # => count=1 doubled=2
counter.count = 10    # => count=10 doubled=20
