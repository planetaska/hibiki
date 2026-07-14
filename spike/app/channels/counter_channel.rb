# frozen_string_literal: true

# Stage-1 spike channel, now written against hibiki_rails (the Phase 3
# proof): the concern owns the actor, the root, the per-action batch, and
# the [channel_name, cid] stream convention — this class is just the graph
# and its actions.
#
# Graph shape kept from the spike questions:
# - two independent effects (count display, step display) prove fine-grained
#   re-render: writing `step` re-broadcasts only #step.
# - `burst` does ten writes in one action; the concern's per-action batch
#   must coalesce them into ONE broadcast per affected effect (watch the
#   [hibiki-spike] log lines).
class CounterChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @count = Hibiki::State.new(0)
    @step = Hibiki::State.new(1)
    doubled = Hibiki::Derived.new { @count.value * 2 }

    Hibiki::Effect.new do
      log_broadcast("count", count: @count.value, doubled: doubled.value)
      broadcast_replace target: "count", partial: "counter/count",
                        locals: { count: @count.value, doubled: doubled.value }
    end

    Hibiki::Effect.new do
      log_broadcast("step", step: @step.value)
      broadcast_replace target: "step", partial: "counter/step",
                        locals: { step: @step.value }
    end
  end

  def increment = @count.value += @step.value

  def set_step(data)
    step = data["step"].to_i
    @step.value = step if step.positive?
  end

  def burst = 10.times { @count.value += 1 }

  private

  def log_broadcast(target, **locals)
    Rails.logger.info("[hibiki-spike] broadcast ##{target} #{locals.inspect}")
  end
end
