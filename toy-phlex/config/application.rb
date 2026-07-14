require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ToyPhlex
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # The entire view layer is Phlex classes, so app/views holds Ruby, not
    # templates — make Zeitwerk load it (app/views/counter/show.rb is
    # Counter::Show).
    config.autoload_paths << root.join("app/views")

    config.generators.system_tests = nil
  end
end
