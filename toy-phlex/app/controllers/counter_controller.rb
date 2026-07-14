# frozen_string_literal: true

class CounterController < ApplicationController
  # Each page load gets its own graph id (same convention as the spike):
  # the CounterChannel subscription carries it, so every tab is an
  # independent connection-scoped graph.
  def show
    render Counter::Show.new(cid: SecureRandom.uuid)
  end
end
