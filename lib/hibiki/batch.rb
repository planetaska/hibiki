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

    # Where effect errors raised during a flush go (Solid's handleError):
    # a callable receiving (error, effect). With a handler set the flush
    # never raises; a raising handler propagates — we don't swallow it.
    # Ractor-local, not a module ivar (IsolationError off the main Ractor)
    # and not Thread.current[] (configuration set once, e.g. in an
    # initializer, must be visible to threads spawned later). Per-Ractor
    # fits the one-independent-world-per-Ractor model.
    def error_handler = Ractor.current[:hibiki_error_handler]

    def error_handler=(handler)
      Ractor.current[:hibiki_error_handler] = handler
    end

    private

    def batch_depth = Thread.current[:hibiki_batch_depth] || 0

    # Swap the queue out before running: an effect may write states and
    # invalidate further effects, and with the batch over those run eagerly.
    #
    # A raising effect must not take the rest of the queue down with it
    # (Solid's runUpdates completes the queue and routes errors to a
    # handler): rescue per effect, finish the flush, then re-raise the
    # first error unless an error_handler took it. StandardError only —
    # Interrupt and friends should still abort the flush.
    def flush_effects
      pending = Thread.current[:hibiki_pending_effects]
      return if pending.nil? || pending.empty?

      Thread.current[:hibiki_pending_effects] = Set.new
      first_error = nil
      pending.each do |effect|
        error = invalidate_isolated(effect)
        first_error ||= error
      end
      raise first_error if first_error
    end

    # One queue entry: run it, and route or return its error instead of
    # raising, so the flush loop always reaches every pending effect.
    def invalidate_isolated(effect)
      effect.invalidate
      nil
    rescue StandardError => e
      handler = error_handler
      return e unless handler

      handler.call(e, effect)
      nil
    end
  end
end
