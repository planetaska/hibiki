# frozen_string_literal: true

module Hibiki
  # ---- batching ---------------------------------------------------------------
  # Coalesces effect runs. Writes inside the block apply immediately — reads
  # always see fresh values, and deriveds stay lazy dirty-flags — but effects
  # invalidated during the block are queued, deduplicated, and run once when
  # the outermost batch exits. Same semantics as Solid's `batch`.
  @batch_depth = 0
  @pending_effects = Set.new

  class << self
    def batch
      @batch_depth += 1
      yield
    ensure
      # Flush even when the block raises: writes before the raise have
      # already landed, so effects must catch up with them.
      @batch_depth -= 1
      flush_effects if @batch_depth.zero?
    end

    def batching? = @batch_depth.positive?

    def schedule(effect) = @pending_effects << effect

    private

    # Swap the queue out before running: an effect may write states and
    # invalidate further effects, and with the batch over those run eagerly.
    def flush_effects
      pending = @pending_effects
      @pending_effects = Set.new
      pending.each(&:invalidate)
    end
  end
end
