# frozen_string_literal: true

require_relative "lib/hibiki/phlex/version"

Gem::Specification.new do |spec|
  spec.name = "hibiki_phlex"
  spec.version = Hibiki::Phlex::VERSION
  spec.authors = ["planetaska"]
  spec.email = ["planetaska@gmail.com"]

  spec.summary = "Phlex glue for hibiki: reactive components re-rendered by a render effect."
  spec.description = <<~DESC.gsub("\n", " ").strip
    Make a Phlex component reactive: include Hibiki::Reactive for signals
    read as plain method calls, Hibiki::Phlex::Rerenderable so the same
    instance can render again, and wrap it in Hibiki::Phlex.render_effect
    to get fresh HTML on every signal change — transport-agnostic, the
    block decides where the HTML goes.
  DESC
  spec.homepage = "https://github.com/planetaska/hibiki"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "hibiki", "~> 0.1"
  # Strict upper bound on purpose: Rerenderable leans on Phlex's private
  # @_state ivar, so allowed minors are an allowlist — bump only after
  # re-verifying the contract (spec/phlex_contract_spec.rb).
  spec.add_dependency "phlex", ">= 2.4", "< 2.5"
end
