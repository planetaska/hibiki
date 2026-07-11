# frozen_string_literal: true

module Hibiki
  # ---- effect -----------------------------------------------------------------
  class Effect
    include Observer # observes, but is never observed (no Trackable)

    def initialize(&block)
      @block = block
      run
    end

    # Under a batch, defer: Hibiki queues us (deduplicated) and re-runs the
    # block once at flush instead of once per write.
    def invalidate
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
