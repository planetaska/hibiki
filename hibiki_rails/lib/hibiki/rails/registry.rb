# frozen_string_literal: true

module Hibiki
  module Rails
    # Tracks every live hibiki channel in the process so the Rails
    # reloader can tear them down: a long-lived graph holds blocks bound
    # to the class versions it was built from, so surviving a code reload
    # would mean effects running stale code forever.
    #
    # NOTE: the core's no-mutex rule is about the GRAPH (confinement, see
    # hibiki's docs-md/threading-model.md). This is glue infrastructure
    # touched from many cable threads; a lock is the right tool here.
    class Registry
      def initialize
        @lock = Mutex.new
        @channels = Set.new
      end

      def register(channel)
        @lock.synchronize { @channels << channel }
      end

      def unregister(channel)
        @lock.synchronize { @channels.delete(channel) }
      end

      def size
        @lock.synchronize { @channels.size }
      end

      # Close each distinct cable connection, which routes every one of
      # its channels through the normal unsubscribed path — dispose root,
      # stop actor, unregister — so teardown has exactly ONE code path and
      # idempotency comes free. Clients auto-reconnect, resubscribe, and
      # #build_graph reruns on fresh class versions; graph state resets,
      # which is inherent to a remount (LiveView does the same).
      def dispose_all
        channels = @lock.synchronize { @channels.to_a }
        channels.map(&:connection).uniq.each(&:close)
      end
    end

    @registry = Registry.new

    class << self
      # Process-wide registry of live hibiki channels.
      attr_reader :registry
    end
  end
end
