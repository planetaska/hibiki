# frozen_string_literal: true

module Hibiki
  # ---- writable signal --------------------------------------------------------
  class State
    include Trackable

    # equals: per-signal equality (Solid's createSignal(value, { equals })).
    # nil → `==`; false → always notify; callable → comparator(prev, next).
    def initialize(value, equals: nil)
      @value = value
      @equals = equals
    end

    def value
      register_dependency
      @value
    end

    # Read without subscribing (per-signal untrack), for read-modify-write
    # effects that must not depend on what they write.
    def peek = @value

    # Solid signals are getter functions; `sig.()` reads (and registers).
    def call = value

    def value=(new_value)
      # The write gate: the signal's equality decides whether this write is a
      # no-op. Its twin is the flush gate, Trackable#changed_from? — keep them
      # answering the same way.
      case @equals
      when nil then return if new_value == @value
      when false then nil # always notify
      else return if @equals.call(@value, new_value)
      end

      @value = new_value
      # Solid wraps every write in runUpdates; mirroring that, an unbatched
      # write becomes an implicit batch of one. The whole invalidation wave
      # (all diamond branches) lands before effects flush, so an effect runs
      # once per write and never sees a half-updated graph.
      Hibiki.batch { notify }
    end

    # sugar for in-place updates: counter.update { it + 1 }
    def update = self.value = yield(@value)

    def to_s = value.to_s
    def inspect = "#<Hibiki::State #{@value.inspect}>"
  end
end
