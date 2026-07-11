# frozen_string_literal: true

module Hibiki
  # ---- batching ---------------------------------------------------------------
  # Coalesces effect runs. Writes inside the block apply immediately — reads
  # always see fresh values, and deriveds stay lazy dirty-flags — but effects
  # invalidated during the block are queued, deduplicated, and run once when
  # the outermost batch exits. Same semantics as Solid's `batch`.
  #
  # Depth and queue are per-execution-context in Thread.current[] — which is
  # fiber-local, not thread-local, despite the name. Deliberately NOT Fiber[]
  # (unlike the observer in tracking.rb): Fiber storage is inherited at fiber
  # creation, and a fiber or thread spawned mid-batch would inherit a nonzero
  # depth it can never unwind — batching? true forever, its effects deferred
  # into a queue nobody flushes. The flush belongs to the exact fiber whose
  # ensure runs it.
  class << self
    def batch
      Thread.current[:hibiki_batch_depth] = batch_depth + 1
      yield
    ensure
      # Flush even when the block raises: writes before the raise have
      # already landed, so effects must catch up with them.
      depth = batch_depth - 1
      Thread.current[:hibiki_batch_depth] = depth
      flush_effects if depth.zero?
    end

    def batching? = batch_depth.positive?

    def schedule(effect) = (Thread.current[:hibiki_pending_effects] ||= Set.new) << effect

    private

    def batch_depth = Thread.current[:hibiki_batch_depth] || 0

    # Swap the queue out before running: an effect may write states and
    # invalidate further effects, and with the batch over those run eagerly.
    def flush_effects
      pending = Thread.current[:hibiki_pending_effects]
      return if pending.nil? || pending.empty?

      Thread.current[:hibiki_pending_effects] = Set.new
      pending.each(&:invalidate)
    end
  end
end
