# frozen_string_literal: true

class CounterController < ApplicationController
  # Each page load gets its own graph id: the Turbo stream subscription and
  # the CounterChannel subscription both carry it, so every tab is an
  # independent connection-scoped graph.
  def show
    @cid = SecureRandom.uuid
  end
end
