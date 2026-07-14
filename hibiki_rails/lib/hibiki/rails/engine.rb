# frozen_string_literal: true

# Railties leans on ActiveSupport's core extensions being loaded; require
# them explicitly so hibiki_rails also loads outside a booted Rails app
# (the gem's own unit specs, a console).
require "active_support"
require "active_support/core_ext"
require "rails/engine"

module Hibiki
  module Rails
    # An Engine (not a bare Railtie) so the vendored client rides Rails'
    # own :append_assets_path initializer: app/assets/javascripts/hibiki.js
    # lands on the host app's asset paths and Propshaft serves it like an
    # app-local file — turbo-rails-style distribution, no install-time copy.
    class Engine < ::Rails::Engine
      # Dev reloading: before code reloads, dispose every live graph — its
      # effects hold blocks from the stale class versions. Also fires once
      # at boot, when the registry is empty (harmless no-op).
      initializer "hibiki_rails.reloader" do |app|
        app.config.to_prepare { Hibiki::Rails.registry.dispose_all }
      end

      # importmap-rails apps get the "hibiki" pin with zero config (the
      # guard keeps jsbundling/vite apps booting; they consume the npm
      # package — or a manual copy — instead).
      initializer "hibiki_rails.importmap", before: "importmap" do |app|
        next unless app.config.respond_to?(:importmap)

        app.config.importmap.paths << Engine.root.join("config/importmap.rb")
      end
    end
  end
end
