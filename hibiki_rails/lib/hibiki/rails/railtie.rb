# frozen_string_literal: true

# Railties leans on ActiveSupport's core extensions being loaded; require
# them explicitly so hibiki_rails also loads outside a booted Rails app
# (the gem's own unit specs, a console).
require "active_support"
require "active_support/core_ext"
require "rails/railtie"

module Hibiki
  module Rails
    class Railtie < ::Rails::Railtie
      # Dev reloading: before code reloads, dispose every live graph — its
      # effects hold blocks from the stale class versions. Also fires once
      # at boot, when the registry is empty (harmless no-op).
      initializer "hibiki_rails.reloader" do |app|
        app.config.to_prepare { Hibiki::Rails.registry.dispose_all }
      end
    end
  end
end
