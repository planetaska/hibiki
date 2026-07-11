# frozen_string_literal: true

module Hibiki
  # ---- observer stack (the heart of runtime dependency tracking) ------------
  @observers = []

  class << self
    def current_observer = @observers.last

    def track(observer)
      @observers.push(observer)
      yield
    ensure
      @observers.pop
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
