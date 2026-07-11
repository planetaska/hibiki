# frozen_string_literal: true

module Hibiki
  # ---- effect -----------------------------------------------------------------
  class Effect
    include Observer # observes, but is never observed (no Trackable)

    def initialize(&block)
      @block = block
      @disposed = false
      @children = []
      # Effects created while another effect runs are owned by it: when the
      # owner re-runs or is disposed, they are disposed too (Solid's owner
      # tree). Otherwise the re-creating rerun would leak live duplicates.
      Hibiki.current_owner&.adopt(self)
      run
    end

    def disposed? = @disposed

    # Sever every subscription and take owned children down with us. A
    # disposed effect never runs again — including a pending batch flush.
    def dispose
      return if @disposed

      @disposed = true
      dispose_children
      clear_sources
    end

    # Under a batch, defer: Hibiki queues us (deduplicated) and re-runs the
    # block once at flush instead of once per write.
    def invalidate
      return if @disposed
      return Hibiki.schedule(self) if Hibiki.batching?

      run
    end

    def adopt(child) = @children << child

    private

    def run
      dispose_children
      clear_sources
      Hibiki.own(self) do
        Hibiki.track(self) { @block.call }
      end
    end

    # Swap the list out first: the rerun adopts fresh children into a
    # clean slate while the previous generation is being disposed.
    def dispose_children
      children = @children
      @children = []
      children.each(&:dispose)
    end
  end
end
