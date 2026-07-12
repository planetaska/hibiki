# frozen_string_literal: true

module Hibiki
  # ---- observer / owner context (the heart of runtime dependency tracking) --
  # Per-execution-context, in Fiber storage (Fiber[], Ruby 3.2+), not module
  # ivars: concurrent contexts must not see each other's tracking windows, and
  # module ivars raise Ractor::IsolationError off the main Ractor. Fiber[] over
  # Thread.current[] (which is fiber-local too, despite the name) because it is
  # inherited at fiber creation — reads inside an Enumerator's internal fiber
  # still register, where uninherited storage would silently drop the edge.
  # The explicit stacks are gone: save/restore around the block makes the call
  # stack the stack.
  class << self
    def current_observer = Fiber[:hibiki_observer]

    def track(observer)
      prev = Fiber[:hibiki_observer]
      Fiber[:hibiki_observer] = observer
      yield
    ensure
      Fiber[:hibiki_observer] = prev
    end

    # Solid's untrack: reads inside the block register nothing. Only the
    # listener is suppressed — the owner slot is left alone, so effects
    # created under untrack are still adopted.
    def untrack(&) = track(nil, &)

    # Solid keeps Owner separate from Listener: only effects own, and a lazy
    # derived computing mid-effect must not steal ownership of effects its
    # block creates. Hence a second slot rather than reusing the observer's.
    def current_owner = Fiber[:hibiki_owner]

    def own(owner)
      prev = Fiber[:hibiki_owner]
      Fiber[:hibiki_owner] = owner
      yield
    ensure
      Fiber[:hibiki_owner] = prev
    end
  end

  # ---- shared subscription behaviour -----------------------------------------
  module Trackable
    def subscribers = (@subscribers ||= Set.new)

    # Called on every read: if someone reactive is currently computing,
    # they now depend on us — record both directions of the edge, so the
    # observer can sever it before its next rerun.
    def register_dependency
      observer = Hibiki.current_observer
      return unless observer

      subscribers << observer
      observer.add_source(self)
    end

    def unsubscribe(observer) = subscribers.delete(observer)

    def notify
      # dup: invalidation may mutate the set while we iterate
      subscribers.dup.each(&:invalidate)
    end
  end

  # ---- shared observer behaviour ----------------------------------------------
  # The reverse edges of Trackable: what an observer read on its last run.
  module Observer
    def sources = (@sources ||= Set.new)
    def add_source(source) = sources << source

    # Solid clears deps before rerun (cleanNode); we mirror that, so stale
    # branches of dynamic deps (flag ? a : b) stop invalidating us.
    def clear_sources
      sources.each { |source| source.unsubscribe(self) }
      sources.clear
    end
  end
end
