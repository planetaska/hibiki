# frozen_string_literal: true

# Minimal in-process Rails app for channel specs — combustion-style, but
# inline and transparent so the harness has no extra dependency. Only what
# the gem touches is loaded: no ActiveRecord, no asset pipeline.
#
# Deliberately NOT spike/: wiring the spike as the spec dummy would couple
# the gem's CI to the spike's Gemfile, and the spike does not travel when
# hibiki_rails is extracted to its own repo.

require "rails"
require "action_controller/railtie"
require "action_cable/engine"
require "turbo-rails"

class DummyApp < Rails::Application
  config.root = File.expand_path("dummy_root", __dir__)
  config.load_defaults 8.0
  config.eager_load = false
  config.logger = ActiveSupport::Logger.new(IO::NULL)
  config.secret_key_base = "hibiki-rails-dummy"
  # have_broadcasted_to reads back from the test pubsub adapter.
  config.action_cable.cable = { "adapter" => "test" }
end

Rails.application.initialize!

# Turbo::Streams::Broadcasts#render_format renders broadcast partials
# through ApplicationController — the dummy app points it at the specs'
# view directory.
class ApplicationController < ActionController::Base
  append_view_path File.expand_path("views", __dir__)
end
