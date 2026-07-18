# frozen_string_literal: true

require "rails/generators"
require_relative "../generator_helpers"

module Hibiki
  module Rails
    module Generators
      # Wiring only — the client itself stays vendored in the engine (the
      # data-hibiki-* attribute names are a private Ruby↔JS contract that
      # versions inside this gem, so the client is never copied into the
      # app; the shim it creates only re-exports it). Every action is
      # idempotent by content check, so rerunning is safe.
      class InstallGenerator < ::Rails::Generators::Base
        include GeneratorHelpers

        source_root File.expand_path("templates", __dir__)

        desc "Wires the packaged hibiki client: registers the \"hibiki\" Stimulus " \
             "controller, includes Hibiki::Rails::Helpers in ApplicationHelper, " \
             "creates the ApplicationCable boilerplate, and pins @rails/actioncable."

        # Exactly the lines `stimulus:manifest:update` emits for the shim,
        # so a later manifest run converges instead of duplicating.
        REGISTER = <<~JS

          import HibikiController from "./hibiki_controller"
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

        # Same event: the stock importmap has no @rails/actioncable pin
        # until the first `rails g channel` adds it. The packaged client
        # imports it, so pin it here (the asset ships in actioncable).
        PIN = <<~RUBY

          pin "@rails/actioncable", to: "actioncable.esm.js"
        RUBY

        # The registration lives in a file-backed shim so that
        # `stimulus:manifest:update` (which rewrites index.js wholesale from
        # the *_controller.js files) re-derives it instead of dropping it.
        def create_shim_controller
          template "hibiki_controller.js.tt", SHIM
        end

        # Importmap apps eager-load the shim from the controllers directory;
        # a manifest-style index.js (jsbundling) must name it explicitly.
        def register_controller
          return legacy_registration_hint if importmap?
          return say_status :identical, INDEX_JS, :blue if wired?(INDEX_JS, REGISTER_FRAGMENT)
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
          return bundler_note unless importmap?
          return say_status :identical, IMPORTMAP, :blue if wired?(IMPORTMAP, "@rails/actioncable")

          append_to_file IMPORTMAP, PIN
        end

        private

        # Installs that predate the shim registered straight in index.js;
        # left in place next to the eager-loaded shim that would register
        # "hibiki" twice.
        def legacy_registration_hint
          return unless wired?(INDEX_JS, REGISTER_FRAGMENT)

          say_status :hint, "#{INDEX_JS} still registers \"hibiki\" directly — " \
                            "remove those lines; the eager-loaded " \
                            "hibiki_controller.js shim replaces them", :yellow
        end

        def bundler_note
          say_status :skip, "#{IMPORTMAP} not found — with a JS bundler, " \
                            "npm/yarn add hibiki-rails instead (it pulls in " \
                            "@rails/actioncable)", :yellow
        end
      end
    end
  end
end
