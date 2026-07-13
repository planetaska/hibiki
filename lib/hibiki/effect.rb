# frozen_string_literal: true

module Hibiki
  # ---- effect -----------------------------------------------------------------
  class Effect
    include Observer # observes, but is never observed (no Trackable)
    include Owner    # owns effects and cleanups registered while running

    def initialize(&block)
      @block = block
      @disposed = false
      # Effects created while another effect (or root) runs are owned by it
      # and disposed when the owner re-runs or is disposed.
      Hibiki.current_owner&.adopt(self)
      run
    end

    def disposed? = @disposed

    # Sever every subscription and take owned children/cleanups down with
    # us. A disposed effect never runs again — including a pending batch
    # flush.
    def dispose
      return if @disposed

      @disposed = true
      dispose_owned
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
      dispose_owned
      clear_sources
      Hibiki.own(self) do
        Hibiki.track(self) { @block.call }
      end
    end
  end
end
