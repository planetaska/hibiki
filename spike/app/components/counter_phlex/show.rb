# frozen_string_literal: true

# The page content, rendered by the controller inside the standard Rails
# layout. This page's reason to exist: the island root and every control
# are stamped by Hibiki::Rails::Helpers splatted into PHLEX element
# methods — the todos page proves the same helpers through ERB tag
# helpers, so between them both documented usage shapes are live.
#
# The two display fragments are rendered here with throwaway zero-value
# signals purely to fill the space on first paint: the channel's live
# instances take over from their first transmit.
class CounterPhlex::Show < Phlex::HTML
  include Hibiki::Rails::Helpers

  def initialize(cid:)
    @cid = cid
  end

  def view_template
    h1 { "Hibiki cable spike — counter (Phlex, packaged client)" }

    div(**hibiki_island(CounterPhlexChannel, cid: @cid)) do
      render CounterPhlex::CountDisplay.new(count: Hibiki::State.new(0),
                                            doubled: Hibiki::State.new(0))
      render CounterPhlex::StepDisplay.new(step: Hibiki::State.new(1))

      p do
        button(**on(:increment)) { "+ step" }
        whitespace
        button(**on(:burst)) { "burst (10 writes, 1 render)" }
        whitespace
        label do
          plain "step: "
          input(type: "number", name: "step", value: "1", min: "1",
                **on(:set_step, event: :change))
        end
      end
    end

    p do
      a(href: "/") { "← ERB stage" }
      whitespace
      plain "·"
      whitespace
      a(href: "/phlex") { "Phlex todos →" }
    end
  end
end
