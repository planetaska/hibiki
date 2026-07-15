# frozen_string_literal: true

# The counter graph again, but on the packaged-client + transmit transport
# (the todos page's shape) with every fragment a Phlex component: two
# independent render effects prove fine-grained re-render (writing `step`
# re-transmits only StepDisplay), and `burst` proves the concern's
# per-action batch (ten writes, one transmit per affected effect). The
# root counter page deliberately stays on Turbo broadcasts as THAT
# transport's live proof — this channel is not a replacement for it.
class CounterPhlexChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @count = Hibiki::State.new(0)
    @step = Hibiki::State.new(1)
    doubled = Hibiki::Derived.new { @count.value * 2 }

    transmit_fragment CounterPhlex::CountDisplay.new(count: @count, doubled:)
    transmit_fragment CounterPhlex::StepDisplay.new(step: @step)
  end

  def increment = @count.value += @step.value

  def set_step(data)
    step = data["step"].to_i
    @step.value = step if step.positive?
  end

  def burst = 10.times { @count.value += 1 }

  private

  # One render effect per fragment; the first run (right here, on the graph
  # thread) is the dependency-collecting initial render, and its transmit
  # reaches the client because the packaged controller registers `received`
  # at subscribe time, before the server ever runs build_graph.
  def transmit_fragment(component)
    Hibiki::Phlex.render_effect(component) do |html|
      Rails.logger.info("[hibiki-spike] render_effect #{component.class} (#{html.bytesize} bytes)")
      transmit({ html: })
    end
  end
end
