# frozen_string_literal: true

require "rails/generators"
require_relative "../generator_helpers"

module Hibiki
  module Rails
    module Generators
      # The Phlex component shape — the component owns the state
      # (Hibiki::Reactive), the channel owns the transport: one render
      # effect re-renders the same instance and transmits the HTML over
      # the channel's own subscription (no Turbo streams involved).
      # Emits a working mini-example: channel + component + an island
      # wrapper component renderable from any page.
      #
      # Generated code needs the hibiki_phlex gem (and phlex-rails to
      # render components from views) — warn, don't fail, when it isn't
      # in the bundle, so the scaffold can come first.
      class PhlexGenerator < ::Rails::Generators::NamedBase
        include GeneratorHelpers

        source_root File.expand_path("templates", __dir__)

        desc "Scaffolds a reactive Phlex component: channel (transmit transport) + " \
             "component + island wrapper. Requires the hibiki_phlex gem."

        def warn_without_hibiki_phlex
          require "hibiki/phlex"
        rescue LoadError
          say_status :warn, "hibiki_phlex is not in this bundle — the generated channel " \
                            "calls Hibiki::Phlex.render_effect. Add `gem \"hibiki_phlex\"` " \
                            "(and `gem \"phlex-rails\"` to render components from views).", :yellow
        end

        def create_channel
          template "channel.rb.tt", "app/channels/#{file_path}_channel.rb"
        end

        def create_component
          template "component.rb.tt", "app/components/#{file_path}.rb"
        end

        def create_island_component
          template "island_component.rb.tt", "app/components/#{file_path}_island.rb"
        end

        def post_install
          say <<~MSG

            Render it from any page:

              <%= render #{class_name}Island.new %>

          MSG
          register_hint
        end

        private

        # The whole component is the transmitted fragment; its root id is
        # the swap key.
        def component_dom_id = name_parts.join("_")

        def register_hint
          return if hibiki_registered?

          say_status :hint, "the packaged client is not registered — run: " \
                            "bin/rails g hibiki:rails:install", :yellow
        end
      end
    end
  end
end
