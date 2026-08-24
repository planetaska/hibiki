# frozen_string_literal: true

# The page content — rendered inside the standard Rails layout
# (layouts/application.html.erb), like any phlex-rails app; the views
# themselves are 100% Phlex. The two display fragments are rendered here
# with throwaway zero-value signals purely to fill the space on first paint:
# the channel's live instances take over from their first transmit (see
# CounterChannel#transmit_fragment).
class Counter::Show < Phlex::HTML
  def initialize(cid:)
    @cid = cid
  end

  def view_template
    h1 { "Hibiki toy — counter (full Phlex)" }

    div(data: { hibiki_channel: "CounterChannel", hibiki_cid: @cid }) do
      render Counter::CountDisplay.new(count: Hibiki::State.new(0),
                                       doubled: Hibiki::State.new(0))
      render Counter::StepDisplay.new(step: Hibiki::State.new(1))

      p do
        button(data: { hibiki_action: "increment" }) { "+ step" }
        whitespace
        button(data: { hibiki_action: "burst" }) { "burst (10 writes, 1 render)" }
        whitespace
        label do
          plain "step: "
          input(type: "number", name: "step", value: "1", min: "1",
                data: { hibiki_change: "set_step" })
        end
      end
    end
  end
end
