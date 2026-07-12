# frozen_string_literal: true

module Hibiki
  # ---- derived / computed -----------------------------------------------------
  class Derived
    include Trackable # observed by downstream deriveds/effects
    include Observer  # observes its own dependencies

    def initialize(&block)
      @block = block
      @dirty = true
    end

    def value
      recompute if @dirty
      register_dependency
      @value
    end

    # Read without subscribing the reader. A dirty derived still recomputes
    # (collecting its own deps as usual) — peek only skips the outward edge.
    def peek
      recompute if @dirty
      @value
    end

    # Solid signals are getter functions; `sig.()` reads (and registers).
    def call = value

    def invalidate
      return if @dirty

      @dirty = true
      notify # propagate dirtiness downstream (derived-of-derived, effects)
    end

    def to_s = value.to_s
    def inspect = "#<Hibiki::Derived #{@dirty ? 'dirty' : @value.inspect}>"

    private

    def recompute
      clear_sources
      @value = Hibiki.track(self) { @block.call }
      @dirty = false
    end
  end
end
