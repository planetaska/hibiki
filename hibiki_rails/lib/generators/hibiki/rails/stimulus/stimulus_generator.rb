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
      # Needs no wiring — the controller autoloads from the controllers
      # directory and the views speak plain Stimulus.
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
      end
    end
  end
end
