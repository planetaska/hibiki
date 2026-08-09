# frozen_string_literal: true

module Hibiki
  # ---- derived / computed -----------------------------------------------------
  class Derived
    include Trackable # observed by downstream deriveds/effects
    include Observer  # observes its own dependencies

    # equals: per-signal equality (Solid's createMemo takes it too). A derived
    # has no write gate, so it matters only at the flush gate — observers ask
    # changed_from?, which consults it (see Trackable).
    def initialize(equals: nil, &block)
      @block = block
      @equals = equals
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
