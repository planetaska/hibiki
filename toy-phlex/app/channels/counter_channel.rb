# frozen_string_literal: true

# The spike's counter graph, but every rendered fragment is a Phlex
# component and the transport is the channel's OWN subscription:
# render_effect's block calls `transmit`, no Turbo stream anywhere. That
# single-subscription shape is what lets the page drop Turbo JS, Stimulus,
# and the stream_connected race helper — the client driver just replaces
# whatever HTML arrives, matched by the fragment's DOM id.
#
# Graph shape kept from the spike: two independent render effects prove
# fine-grained re-render (writing `step` re-transmits only StepDisplay),
# and `burst` proves the concern's per-action batch (ten writes, one
# transmit per affected effect — watch the [hibiki-toy] log lines).
class CounterChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @count = Hibiki::State.new(0)
    @step = Hibiki::State.new(1)
    doubled = Hibiki::Derived.new { @count.value * 2 }

    transmit_fragment Counter::CountDisplay.new(count: @count, doubled:)
    transmit_fragment Counter::StepDisplay.new(step: @step)
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
  # reaches the client because the driver's subscription callbacks are
  # registered before the server ever runs build_graph.
  def transmit_fragment(component)
    Hibiki::Phlex.render_effect(component) do |html|
      Rails.logger.info("[hibiki-toy] transmit #{component.class} (#{html.bytesize} bytes)")
      transmit({ html: })
    end
  end
end
