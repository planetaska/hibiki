# frozen_string_literal: true

class CounterPhlexController < ApplicationController
  # Each page load gets its own graph id (same convention as the other
  # pages): the CounterPhlexChannel subscription carries it, so every tab
  # is an independent connection-scoped graph.
  def show
    render CounterPhlex::Show.new(cid: SecureRandom.uuid)
  end
end
