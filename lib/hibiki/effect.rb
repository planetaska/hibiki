# frozen_string_literal: true

module Hibiki
  # ---- effect -----------------------------------------------------------------
  class Effect
    include Observer # observes, but is never observed (no Trackable)

    def initialize(&block)
      @block = block
      @disposed = false
      run
    end

    def disposed? = @disposed

    # Sever every subscription so the effect never runs again — including
    # a pending batch flush (`invalidate` no-ops once disposed).
    def dispose
      return if @disposed

      @disposed = true
      clear_sources
    end

    # Under a batch, defer: Hibiki queues us (deduplicated) and re-runs the
    # block once at flush instead of once per write.
    def invalidate
      return if @disposed
      return Hibiki.schedule(self) if Hibiki.batching?

      run
    end

    private

    def run
      clear_sources
      Hibiki.track(self) { @block.call }
    end
  end
end
