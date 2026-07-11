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
    # they now depend on us.
    def register_dependency
      observer = Hibiki.current_observer
      subscribers << observer if observer
    end

    def notify
      # dup: invalidation may mutate the set while we iterate
      subscribers.dup.each(&:invalidate)
    end
  end
end
