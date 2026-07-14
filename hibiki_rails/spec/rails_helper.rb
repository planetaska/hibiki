# frozen_string_literal: true

require "spec_helper"
require_relative "support/dummy_app"
require "rspec/rails"

RSpec.configure do |config|
  # Tear down any live subscription so examples don't leak graph actors
  # or Hibiki::Rails.registry entries into each other.
  config.after(type: :channel) do
    subscription.unsubscribe_from_channel if subscription&.confirmed?
  end
end
