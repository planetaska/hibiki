# frozen_string_literal: true

require "rails/generators"

module Hibiki
  module Rails
    module Generators
      # Shared naming and wiring-detection helpers for the hibiki:rails:*
      # generators. The naming helpers ride on NamedBase's name parts
      # (regular_class_path / file_name); the wiring predicates only need
      # destination_root, so the install generator uses them too.
      module GeneratorHelpers
        INDEX_JS = "app/javascript/controllers/index.js"
        APPLICATION_HELPER = "app/helpers/application_helper.rb"
        REGISTER_FRAGMENT = 'application.register("hibiki"'
        IMPORTMAP = "config/importmap.rb"

        private

        # First streamable of the concern's [channel_name, cid] convention:
        # ActionCable's channel_name for Admin::CounterChannel is
        # "admin:counter".
        def stream_name = name_parts.join(":")

        # The Stimulus identifier Rails derives from
        # app/javascript/controllers/<file_path>_controller.js.
        def identifier = name_parts.join("--").tr("_", "-")

        # Root id of the replaced fragment — namespaced with the component's
        # own name so several generated islands can share a page.
        def display_dom_id = "#{name_parts.join('_')}_display"

        def nested? = !regular_class_path.empty?

        def name_parts = regular_class_path + [file_name]

        def hibiki_registered? = wired?(INDEX_JS, REGISTER_FRAGMENT)

        def helpers_included? = wired?(APPLICATION_HELPER, "Hibiki::Rails::Helpers")

        # importmap-rails apps eager-load the controllers directory;
        # jsbundling apps register each controller in index.js by hand.
        def importmap? = exists?(IMPORTMAP)

        def exists?(path) = File.exist?(File.join(destination_root, path))

        def wired?(path, fragment)
          full = File.join(destination_root, path)
          File.exist?(full) && File.read(full).include?(fragment)
        end

        def manual_wiring(path, snippet)
          say_status :skip, "#{path} not found — add this yourself:", :yellow
          say snippet
        end
      end
    end
  end
end
