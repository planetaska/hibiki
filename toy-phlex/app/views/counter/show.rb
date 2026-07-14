# frozen_string_literal: true

# The whole page — doctype to </html> — is this one Phlex view; the app has
# no ERB templates and no layout file. The two display fragments are
# rendered here with throwaway zero-value signals purely as paint-avoidance
# placeholders: the channel's live instances take over from their first
# transmit (see CounterChannel#transmit_fragment).
class Counter::Show < Phlex::HTML
  include Phlex::Rails::Helpers::JavaScriptImportmapTags

  def initialize(cid:)
    @cid = cid
  end

  def view_template
    doctype
    html do
      head do
        title { "Hibiki toy — counter (full Phlex)" }
        meta(name: "viewport", content: "width=device-width,initial-scale=1")
        javascript_importmap_tags
      end
      body do
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
  end
end
