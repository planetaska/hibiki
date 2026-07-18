# frozen_string_literal: true

require "rails/generators"
require_relative "../generator_helpers"

module Hibiki
  module Rails
    module Generators
      # Wiring only — the client itself stays vendored in the engine (the
      # data-hibiki-* attribute names are a private Ruby↔JS contract that
      # versions inside this gem, so nothing is ever copied into the app).
      # Both actions are idempotent by content check, so rerunning is safe.
      class InstallGenerator < ::Rails::Generators::Base
        include GeneratorHelpers

        desc "Wires the packaged hibiki client: registers the \"hibiki\" Stimulus " \
             "controller and includes Hibiki::Rails::Helpers in ApplicationHelper."

        REGISTER = <<~JS

          // The packaged hibiki client (vendored by the hibiki_rails engine,
          // pinned as "hibiki"). The identifier must be "hibiki" — the Ruby
          // helpers hardcode it in data-controller.
          import HibikiController from "hibiki"
          application.register("hibiki", HibikiController)
        JS

        INCLUDE_LINE = "  include Hibiki::Rails::Helpers\n"

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

        private

        def exists?(path) = File.exist?(File.join(destination_root, path))

        def manual_wiring(path, snippet)
          say_status :skip, "#{path} not found — add this yourself:", :yellow
          say snippet
        end
      end
    end
  end
end
