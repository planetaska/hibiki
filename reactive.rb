# reactive.rb — a minimal Svelte-5-style signal system in Ruby.
#
# Three primitives, same as Solid/Svelte 5 internals:
#   state(v)      -> writable signal
#   derived { }   -> lazy computed signal with runtime dependency tracking
#   effect { }    -> side effect that re-runs when its dependencies change
#
# Dependency tracking works exactly like the JS frameworks: while a derived
# or effect is (re)computing, it is pushed onto an "observer stack". Any
# signal whose value is READ during that window registers the observer as a
# subscriber. Writes then invalidate subscribers transitively.

require "set"

module Reactive
  # ---- observer stack (the heart of runtime dependency tracking) ----------
  @observers = []

  class << self
    def current_observer = @observers.last

    def track(observer)
      @observers.push(observer)
      yield
    ensure
      @observers.pop
    end
  end

  # ---- shared subscription behaviour ---------------------------------------
  module Trackable
    def subscribers = (@subscribers ||= Set.new)

    # Called on every read: if someone reactive is currently computing,
    # they now depend on us.
    def register_dependency
      observer = Reactive.current_observer
      subscribers << observer if observer
    end

    def notify
      # dup: invalidation may mutate the set while we iterate
      subscribers.dup.each(&:invalidate)
    end
  end

  # ---- writable signal ------------------------------------------------------
  class State
    include Trackable

    def initialize(value)
      @value = value
    end

    def value
      register_dependency
      @value
    end

    def value=(new_value)
      return if new_value == @value
      @value = new_value
      notify
    end

    # sugar for in-place updates: counter.update { _1 + 1 }
    def update = self.value = yield(@value)

    def to_s = value.to_s
    def inspect = "#<Reactive::State #{@value.inspect}>"
  end

  # ---- derived / computed ---------------------------------------------------
  class Derived
    include Trackable

    def initialize(&block)
      @block = block
      @dirty = true
    end

    def value
      recompute if @dirty
      register_dependency
      @value
    end

    def invalidate
      return if @dirty
      @dirty = true
      notify # propagate dirtiness downstream (derived-of-derived, effects)
    end

    def to_s = value.to_s
    def inspect = "#<Reactive::Derived #{@dirty ? 'dirty' : @value.inspect}>"

    private

    def recompute
      @value = Reactive.track(self) { @block.call }
      @dirty = false
    end
  end

  # ---- effect ---------------------------------------------------------------
  class Effect
    def initialize(&block)
      @block = block
      run
    end

    def invalidate = run

    private

    def run
      Reactive.track(self) { @block.call }
    end
  end

  # ---- top-level DSL --------------------------------------------------------
  module DSL
    def state(value)    = State.new(value)
    def derived(&block) = Derived.new(&block)
    def effect(&block)  = Effect.new(&block)
  end
end

include Reactive::DSL