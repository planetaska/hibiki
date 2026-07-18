# frozen_string_literal: true

require "rails/generators"
require_relative "../generator_helpers"

module Hibiki
  module Rails
    module Generators
      # The ChannelController shape — stock Stimulus vocabulary
      # (data-controller / data-action) over the Turbo-broadcast transport.
      # Emits a working mini-example (one state, one derived, one action,
      # one broadcasting effect) meant to be reshaped in place: a channel,
      # a ChannelController subclass, and a self-contained view partial.
      # Importmap apps need no wiring — the controller eager-loads from the
      # controllers directory; jsbundling apps get the import/register pair
      # appended to controllers/index.js (stimulus:manifest:update format).
      class StimulusGenerator < ::Rails::Generators::NamedBase
        include GeneratorHelpers

        source_root File.expand_path("templates", __dir__)

        desc "Scaffolds a reactive component on the subclassable ChannelController " \
             "base: channel + Stimulus controller + a self-contained view partial."

        argument :view_path, type: :string, required: false, default: nil,
                             desc: "Views directory under app/views (default: NAME)"

        def create_channel
          template "channel.rb.tt", "app/channels/#{file_path}_channel.rb"
        end

        def create_controller
          template "controller.js.tt", "app/javascript/controllers/#{file_path}_controller.js"
        end

        # Without an importmap there is no eager loader, so the manifest-style
        # index.js must name every controller. Mirror the exact lines
        # `stimulus:manifest:update` would emit for this file.
        def register_controller
          return if importmap?
          return say_status :identical, INDEX_JS, :blue if wired?(INDEX_JS, %(register("#{identifier}")))
          return manual_wiring(INDEX_JS, registration) unless exists?(INDEX_JS)

          append_to_file INDEX_JS, "\n#{registration}"
        end

        def create_views
          template "island.html.erb.tt", "app/views/#{view_dir}/_#{file_name}.html.erb"
          template "display.html.erb.tt", "app/views/#{view_dir}/_#{file_name}_display.html.erb"
        end

        def post_install
          say <<~MSG

            Render it from any page:

              <%= render "#{view_dir}/#{file_name}" %>

          MSG
        end

        private

        def view_dir = view_path.presence || file_path

        # Stimulus::Manifest's class-name convention: Admin__CounterController.
        def js_class_name = "#{name_parts.map(&:camelize).join('__')}Controller"

        def registration
          <<~JS
            import #{js_class_name} from "./#{file_path}_controller"
            application.register("#{identifier}", #{js_class_name})
          JS
        end
      end
    end
  end
end
