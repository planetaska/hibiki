# frozen_string_literal: true

module Hibiki
  # ---- derived / computed -----------------------------------------------------
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
    def inspect = "#<Hibiki::Derived #{@dirty ? 'dirty' : @value.inspect}>"

    private

    def recompute
      @value = Hibiki.track(self) { @block.call }
      @dirty = false
    end
  end
end
