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

    # Solid's onCleanup: registers on the current OWNER, not the listener —
    # a lazy derived computing mid-effect registers cleanups on the effect,
    # matching how effects created there are adopted. The block runs before
    # the owner's next rerun and on dispose. Outside any owner it can never
    # run; mirror Solid and warn rather than raise.
    def on_cleanup(&block)
      owner = current_owner
      return warn("Hibiki.on_cleanup: no current owner (effect or root); the cleanup can never run") unless owner

      owner.add_cleanup(block)
      block
    end
  end

  # ---- shared subscription behaviour -----------------------------------------
  module Trackable
    def subscribers = (@subscribers ||= Set.new)

    # Called on every read: if someone reactive is currently computing,
    # they now depend on us — record both directions of the edge, so the
    # observer can sever it before its next rerun.
    #
    # The VALUE travels with the edge: an observer that remembers what it saw
    # can decide later whether anything it reads actually changed (Svelte's
    # $derived compares; see Observer#sources_changed?). `peek` is the
    # documented read-without-an-edge, and we're already clean here — a
    # Derived recomputes before it registers — so it costs a cache read.
    def register_dependency
      observer = Hibiki.current_observer
      return unless observer

      subscribers << observer
      observer.add_source(self, peek)
    end

    def unsubscribe(observer) = subscribers.delete(observer)

    def notify
      # dup: invalidation may mutate the set while we iterate
      subscribers.dup.each(&:invalidate)
    end
  end

  # ---- shared observer behaviour ----------------------------------------------
  # The reverse edges of Trackable: what an observer read on its last run, and
  # the value each one had when it read it.
  module Observer
    # source => the value we saw for it. A Hash rather than a Set because the
    # remembered value is what makes the equality gate possible; last read in
    # a run wins, which is the value the run actually acted on.
    def sources = (@sources ||= {})
    def add_source(source, seen) = sources[source] = seen

    # Solid clears deps before rerun (cleanNode); we mirror that, so stale
    # branches of dynamic deps (flag ? a : b) stop invalidating us.
    def clear_sources
      sources.each_key { |source| source.unsubscribe(self) }
      sources.clear
    end

    # The equality gate, asked at flush time (see Effect#invalidate): did any
    # value we read actually change? Svelte's $derived compares; we compare on
    # the observer's side instead of the producer's, because Derived#invalidate
    # has already notified downstream by the time it knows its new value.
    #
    # `peek` resolves a dirty source without subscribing us to it — no untrack
    # needed, since a Derived#recompute makes itself the observer. `any?`
    # short-circuits in the useful direction: sources are in read order, so a
    # changed first source spares the rest a validation recompute, and the run
    # recomputes them only if it reads them this time.
    def sources_changed?
      sources.any? { |source, seen| source.peek != seen }
    end
  end

  # ---- shared owner behaviour ---------------------------------------------------
  # Solid's Owner half of a computation: effects and roots own the child
  # effects and cleanups registered while their block runs, and tear them
  # down together on rerun/dispose.
  module Owner
    # Effects created while our block runs become ours: when we re-run or
    # are disposed, they are disposed too (Solid's owner tree). Otherwise a
    # re-creating rerun would leak live duplicates.
    def adopt(child) = (@children ||= []) << child

    def add_cleanup(block) = (@cleanups ||= []) << block

    private

    # Solid's cleanNode: children go down before our own cleanups run (a
    # child's cleanup may still need a resource ours tears down), cleanups
    # in LIFO order like nested ensure blocks. Both lists are swapped out
    # first, so a rerun adopts fresh entries into a clean slate while the
    # previous generation is being torn down.
    def dispose_owned
      children = @children || []
      @children = []
      children.each(&:dispose)

      cleanups = @cleanups || []
      @cleanups = []
      cleanups.reverse_each(&:call)
    end
  end
end
