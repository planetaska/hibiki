# frozen_string_literal: true

# Stage-1 spike channel: a connection-scoped hibiki graph pushing ERB
# partials over Turbo Streams.
#
#   cable action arrives -> actor thread mutates signals inside a batch ->
#   effects re-render partials -> Turbo::StreamsChannel.broadcast_replace_to
#
# Graph shape chosen to exercise the spike questions:
# - two independent effects (count display, step display) prove fine-grained
#   re-render: writing `step` re-broadcasts only #step.
# - `burst` does ten writes in one action; the batch must coalesce them into
#   ONE broadcast per affected effect (watch the [hibiki-spike] log lines).
class CounterChannel < ApplicationCable::Channel
  def subscribed
    @cid = params[:cid]
    return reject if @cid.blank?

    @actor = GraphActor.new
    @actor.post { build_graph }
  end

  def unsubscribed
    return unless @actor

    @actor.post { @root.dispose }
    @actor.stop
  end

  def increment
    act { @count.value += @step.value }
  end

  def set_step(data)
    step = data["step"].to_i
    act { @step.value = step } if step.positive?
  end

  def burst
    act { 10.times { @count.value += 1 } }
  end

  private

  # Every action mutates the graph on the actor thread, inside one batch —
  # the "is Hibiki.batch around each action enough?" question.
  def act(&mutation)
    @actor.post { Hibiki.batch(&mutation) }
  end

  def build_graph
    @root = Hibiki.root do
      @count = Hibiki::State.new(0)
      @step = Hibiki::State.new(1)
      doubled = Hibiki::Derived.new { @count.value * 2 }

      Hibiki::Effect.new do
        broadcast_partial("count", partial: "counter/count",
                          locals: { count: @count.value, doubled: doubled.value })
      end

      Hibiki::Effect.new do
        broadcast_partial("step", partial: "counter/step",
                          locals: { step: @step.value })
      end
    end
  end

  def broadcast_partial(target, partial:, locals:)
    Rails.logger.info("[hibiki-spike] broadcast ##{target} #{locals.inspect}")
    Turbo::StreamsChannel.broadcast_replace_to("counter", @cid, target:, partial:, locals:)
  end
end
