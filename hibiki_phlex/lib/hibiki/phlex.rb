# frozen_string_literal: true

# NOTE: for everything under lib/hibiki/phlex/ — inside this namespace a bare
# `Phlex` constant resolves to Hibiki::Phlex, not the framework. Always
# write `::Phlex.` when you mean the framework.
module Hibiki
  # Phlex glue for hibiki: a component is a plain Ruby object, so
  # Hibiki::Reactive gives it signals read as ordinary method calls, and a
  # render effect re-renders the same instance (signal identity lives in
  # the instance) whenever one of them changes.
  module Phlex
  end
end

require_relative "phlex/version"
require_relative "phlex/rerenderable"
