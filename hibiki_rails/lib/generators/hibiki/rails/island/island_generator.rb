# frozen_string_literal: true

require "rails/generators"
require_relative "../generator_helpers"

module Hibiki
  module Rails
    module Generators
      # The island shape — the packaged generic "hibiki" controller drives
      # the island, so there is NO per-component JS: a channel and a
      # self-contained view partial stamped through Hibiki::Rails::Helpers
      # (never raw data-hibiki-* attributes — that contract is private to
      # the gem). Emits the same working mini-example as the stimulus
      # shape, over the same Turbo-broadcast transport.
      #
      # Needs the one-time wiring from hibiki:rails:install (the register
      # line + the Helpers include); post_install hints when it's missing.
      class IslandGenerator < ::Rails::Generators::NamedBase
        include GeneratorHelpers

        source_root File.expand_path("templates", __dir__)

        desc "Scaffolds a reactive island on the packaged \"hibiki\" controller: " \
             "channel + a self-contained view partial, no per-component JS."

        argument :view_path, type: :string, required: false, default: nil,
                             desc: "Views directory under app/views (default: NAME)"

        def create_channel
          template "channel.rb.tt", "app/channels/#{file_path}_channel.rb"
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
          wiring_hint
        end

        private

        def view_dir = view_path.presence || file_path

        def wiring_hint
          return if hibiki_registered? && helpers_included?

          say_status :hint, "the packaged client is not fully wired " \
                            "(register line and/or Helpers include) — run: " \
                            "bin/rails g hibiki:rails:install", :yellow
        end
      end
    end
  end
end
