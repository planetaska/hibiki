# frozen_string_literal: true

# Funnels all access to one connection's signal graph through a single
# worker thread. ActionCable dispatches incoming commands on a thread pool
# with no per-channel ordering guarantee, while hibiki's threading model is
# confinement without locks — so the graph is built, mutated, and disposed
# on exactly one thread, and cable threads only ever enqueue closures.
#
# This is the phase-3 "per-graph action serialization" candidate for
# hibiki_rails; the spike exists partly to find the right shape for it.
class GraphActor
  def initialize
    @queue = Queue.new
    @thread = Thread.new do
      while (job = @queue.pop)
        begin
          job.call
        rescue StandardError => e
          Rails.logger.error("[hibiki-spike] actor job failed: #{e.class}: #{e.message}")
        end
      end
    end
    @thread.name = "hibiki-graph-actor"
  end

  def post(&job)
    @queue << job
  end

  # Closing (rather than clearing) the queue lets already-posted jobs — in
  # particular the dispose posted from `unsubscribed` — drain before the
  # worker exits.
  def stop
    @queue.close
  end
end
