# frozen_string_literal: true

module Hibiki
  # ---- effect -----------------------------------------------------------------
  class Effect
    include Observer # observes, but is never observed (no Trackable)

    def initialize(&block)
      @block = block
      run
    end

    def invalidate = run

    private

    def run
      clear_sources
      Hibiki.track(self) { @block.call }
    end
  end
end
