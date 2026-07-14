# frozen_string_literal: true

# NOTE: for everything under lib/hibiki/rails/ — inside this namespace a bare
# `Rails` constant resolves to Hibiki::Rails, not the framework. Always
# write `::Rails.` when you mean the framework.
module Hibiki
  # Rails glue for hibiki: connection-scoped signal graphs over ActionCable,
  # pushing re-rendered HTML through Turbo Streams.
  module Rails
  end
end

require_relative "rails/version"
