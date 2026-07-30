# frozen_string_literal: true

module Hibiki
  # ---- effect -----------------------------------------------------------------
  class Effect
    include Observer # observes, but is never observed (no Trackable)
    include Owner    # owns effects and cleanups registered while running

    # scheduler: hands re-runs to the caller instead of running inline
    # (Vue's ReactiveEffect scheduler): a callable receiving the effect,
    # which calls #run whenever it's ready — on the graph's own execution
    # context. The initial run is never scheduled: dependency collection
    # must happen at creation, and Vue's constructor runs directly too.
    def initialize(scheduler: nil, &block)
      @block = block
      @scheduler = scheduler
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
    # block once at flush instead of once per write. With a scheduler, the
    # re-run is handed to it right where it would have happened — after the
    # batch dedup, so the flush's error isolation covers a raising scheduler
    # too, and N batched writes mean one scheduler call.
    #
    # Past the batching? check we are at the flush, which is where the equality
    # gate belongs: every write in the wave has landed, so asking the sources
    # whether anything changed reads a consistent graph (a diamond validates
    # once, against both legs). Nothing changed means nothing to do — not even
    # a scheduler call, so a debounced broadcast never fires for a no-op.
    #
    # own(self) because validation may recompute a derived whose block
    # registers an on_cleanup or creates an effect: this effect's own run is
    # where that would otherwise have landed. Deriveds are values, not owners —
    # a block with side effects was already at the mercy of whoever reads first.
    def invalidate
      return if @disposed
      return Hibiki.schedule(self) if Hibiki.batching?
      return unless Hibiki.own(self) { sources_changed? }
      return @scheduler.call(self) if @scheduler

      run
    end

    # Public for scheduled effects: the scheduler (or whoever it handed us
    # to) calls this when it's time to re-run. No-op once disposed — a
    # debounced run firing late must lose to dispose, like a pending flush
    # does. A raise propagates to the caller: a deferred run is outside any
    # flush, so the integration owns rescue there.
    def run
      return if @disposed

      dispose_owned
      clear_sources
      Hibiki.own(self) do
        Hibiki.track(self) { @block.call }
      end
    end
  end
end
