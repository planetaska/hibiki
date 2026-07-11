# frozen_string_literal: true

require_relative "lib/hibiki/version"

Gem::Specification.new do |spec|
  spec.name = "hibiki"
  spec.version = Hibiki::VERSION
  spec.authors = ["planetaska"]
  spec.email = ["planetaska@gmail.com"]

  spec.summary = "Svelte-5-style signals for Ruby: state, derived, effect."
  spec.description = <<~DESC.gsub("\n", " ").strip
    A fine-grained reactivity library modeled on the signal systems in
    Svelte 5 and SolidJS. Runtime dependency tracking, not static analysis:
    while a derived or effect computes, any signal read during that window
    subscribes it. Writable state, lazy derived values, and eager effects.
  DESC
  spec.homepage = "https://github.com/planetaska/hibiki"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]

  # No runtime dependencies — core invariant of this gem.
end
