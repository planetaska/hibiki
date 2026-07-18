# frozen_string_literal: true

require "rails/generators"
require_relative "../generator_helpers"

module Hibiki
  module Rails
    module Generators
      # Wiring only — the client itself stays vendored in the engine (the
      # data-hibiki-* attribute names are a private Ruby↔JS contract that
      # versions inside this gem, so nothing is ever copied into the app).
      # Every action is idempotent by content check, so rerunning is safe.
      class InstallGenerator < ::Rails::Generators::Base
        include GeneratorHelpers

        source_root File.expand_path("templates", __dir__)

        desc "Wires the packaged hibiki client: registers the \"hibiki\" Stimulus " \
             "controller, includes Hibiki::Rails::Helpers in ApplicationHelper, " \
             "creates the ApplicationCable boilerplate, and pins @rails/actioncable."

        REGISTER = <<~JS

          // The packaged hibiki client (vendored by the hibiki_rails engine,
          // pinned as "hibiki"). The identifier must be "hibiki" — the Ruby
          // helpers hardcode it in data-controller.
          import HibikiController from "hibiki"
          application.register("hibiki", HibikiController)
        JS

        INCLUDE_LINE = "  include Hibiki::Rails::Helpers\n"

        # Stock Rails apps don't have these until the first `rails g
        # channel` — the hibiki:rails:* generators write their channels
        # directly, so install supplies the boilerplate they inherit.
        APPLICATION_CABLE = {
          "channel.rb.tt" => "app/channels/application_cable/channel.rb",
          "connection.rb.tt" => "app/channels/application_cable/connection.rb"
        }.freeze

        IMPORTMAP = "config/importmap.rb"

        # Same event: the stock importmap has no @rails/actioncable pin
        # until the first `rails g channel` adds it. The packaged client
        # imports it, so pin it here (the asset ships in actioncable).
        PIN = <<~RUBY

          pin "@rails/actioncable", to: "actioncable.esm.js"
        RUBY

        def register_controller
          return say_status :identical, INDEX_JS, :blue if hibiki_registered?
          return manual_wiring(INDEX_JS, REGISTER) unless exists?(INDEX_JS)

          append_to_file INDEX_JS, REGISTER
        end

        def include_helpers
          return say_status :identical, APPLICATION_HELPER, :blue if helpers_included?
          return manual_wiring(APPLICATION_HELPER, INCLUDE_LINE) unless exists?(APPLICATION_HELPER)

          inject_into_file APPLICATION_HELPER, INCLUDE_LINE,
                           after: /module ApplicationHelper\s*\n/
        end

        # Presence is enough — an app's own ApplicationCable (customized
        # or not) is never touched.
        def create_application_cable
          APPLICATION_CABLE.each do |source, destination|
            next say_status :exist, destination, :blue if exists?(destination)

            template source, destination
          end
        end

        def pin_actioncable
          return bundler_note unless exists?(IMPORTMAP)
          return say_status :identical, IMPORTMAP, :blue if wired?(IMPORTMAP, "@rails/actioncable")

          append_to_file IMPORTMAP, PIN
        end

        private

        def exists?(path) = File.exist?(File.join(destination_root, path))

        def manual_wiring(path, snippet)
          say_status :skip, "#{path} not found — add this yourself:", :yellow
          say snippet
        end

        def bundler_note
          say_status :skip, "#{IMPORTMAP} not found — with a JS bundler, make " \
                            "\"@rails/actioncable\" resolvable instead " \
                            "(e.g. npm/yarn add @rails/actioncable)", :yellow
        end
      end
    end
  end
end
