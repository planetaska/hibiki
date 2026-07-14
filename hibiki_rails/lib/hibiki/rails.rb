# frozen_string_literal: true

# NOTE: for everything under lib/hibiki/rails/ — inside this namespace a bare
# `Rails` constant resolves to Hibiki::Rails, not the framework. Always
# write `::Rails.` when you mean the framework.
module Hibiki
  # Rails glue for hibiki: connection-scoped signal graphs over ActionCable,
  # pushing re-rendered HTML through Turbo Streams.
  module Rails
    # Default per-job error sink for GraphActor: the Rails error reporter,
    # so a raising action shows up wherever the app already sends errors.
    # This is the outer layer of the funnel — a flush error first goes to
    # an app-set Hibiki.error_handler if there is one, and only re-raises
    # into the actor's per-job rescue when there isn't.
    def self.default_error_reporter
      ->(error) { ::Rails.error.report(error, handled: true, source: "hibiki_rails") }
    end
  end
end

require_relative "rails/version"
require_relative "rails/graph_actor"
