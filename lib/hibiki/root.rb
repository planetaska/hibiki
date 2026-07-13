# frozen_string_literal: true

module Hibiki
  # ---- root -------------------------------------------------------------------
  # Solid's createRoot: an ownership scope that is not an effect. Effects
  # and cleanups created inside the block belong to the root and live until
  # #dispose — the lifecycle anchor for long-lived graphs (a session, a
  # connection) whose teardown is an external event, not a rerun.
  #
  # Deliberately detached: a root created inside a running effect is NOT
  # adopted, so the enclosing effect's rerun/disposal leaves it alone
  # (Solid's escape hatch from the owner tree). Whoever holds the root
  # disposes it.
  #
  # The block runs untracked (Solid clears the Listener in createRoot): a
  # root built mid-effect must not subscribe that effect to signals it
  # reads.
  class Root
    include Owner

    def initialize(&block)
      @disposed = false
      Hibiki.own(self) do
        Hibiki.untrack { block.call(self) }
      end
    end

    def disposed? = @disposed

    def dispose
      return if @disposed

      @disposed = true
      dispose_owned
    end
  end

  class << self
    # Hibiki.root { |root| ... } — build a graph inside an ownership scope;
    # tear the whole thing down later with root.dispose. Unlike Solid
    # (which returns the block's result and yields a dispose function) the
    # root itself is yielded AND returned: in Ruby the caller, not the
    # block, typically owns teardown.
    def root(&) = Root.new(&)
  end
end
