# frozen_string_literal: true

module Hibiki
  module Rails
    # Funnels all access to one connection's signal graph through a single
    # worker thread. ActionCable dispatches incoming commands on a thread
    # pool with no per-channel ordering guarantee, while hibiki's threading
    # model is confinement without locks — so the graph is built, mutated,
    # and disposed on exactly one thread, and cable threads only ever
    # enqueue closures.
    #
    # Thread-per-graph is deliberate while the gem incubates; a pooled
    # executor with per-graph ordering can replace it behind
    # Channel#build_graph_actor once real numbers ask for one.
    class GraphActor
      def initialize(name: "hibiki-graph", on_error: Hibiki::Rails.default_error_reporter)
        @on_error = on_error
        @queue = Queue.new
        @thread = Thread.new { work }
        @thread.name = name # keep <= 15 chars: Linux truncates pthread names
      end

      # Enqueue a closure for the worker. Returns false (rather than
      # raising) once stopped: an action can race teardown, and a cable
      # thread must never blow up because the user just navigated away.
      def post(&job)
        @queue << job
        true
      rescue ClosedQueueError
        false
      end

      # Queue#close, not clear: already-posted jobs — in particular the
      # root dispose posted from unsubscribed — drain before the worker
      # exits. Idempotent. `wait: true` joins the worker; specs use it as
      # a deterministic drain barrier.
      def stop(wait: false)
        @queue.close
        @thread.join if wait
        nil
      end

      def stopped? = @queue.closed?

      private

      # Per-job rescue keeps the worker alive: one bad action must not take
      # the whole graph down. StandardError only — an Interrupt should.
      def work
        while (job = @queue.pop)
          begin
            job.call
          rescue StandardError => e
            @on_error.call(e)
          end
        end
      end
    end
  end
end
