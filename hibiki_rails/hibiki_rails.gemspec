# frozen_string_literal: true

require_relative "lib/hibiki/rails/version"

Gem::Specification.new do |spec|
  spec.name = "hibiki_rails"
  spec.version = Hibiki::Rails::VERSION
  spec.authors = ["planetaska"]
  spec.email = ["planetaska@gmail.com"]

  spec.summary = "Rails glue for hibiki: connection-scoped signal graphs over ActionCable + Turbo Streams."
  spec.description = <<~DESC.gsub("\n", " ").strip
    Run a hibiki signal graph per ActionCable connection: build it in
    subscribed, mutate it from channel actions (batched, confined to one
    worker thread), and let effects push re-rendered partials to the page
    through Turbo Streams.
  DESC
  spec.homepage = "https://github.com/planetaska/hibiki"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "app/assets/javascripts/*.js",
                   "config/importmap.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actioncable", ">= 8.0"
  spec.add_dependency "hibiki", "~> 0.1"
  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "turbo-rails", ">= 2.0"
end
