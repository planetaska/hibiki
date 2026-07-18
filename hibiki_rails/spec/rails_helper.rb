# frozen_string_literal: true

require "spec_helper"
require_relative "support/dummy_app"
require "rspec/rails"

RSpec.configure do |config|
  # Tear down any live subscription so examples don't leak graph actors
  # or Hibiki::Rails.registry entries into each other. stop(wait: true)
  # joins the worker so the dispose posted by unsubscribed lands inside
  # THIS example — unjoined, a slow runner can flush it into the next
  # example's class-level probes (CI-only flake at seed 27727).
  config.after(type: :channel) do
    if subscription&.confirmed?
      subscription.unsubscribe_from_channel
      subscription.instance_variable_get(:@__hibiki_actor)&.stop(wait: true)
    end
  end
end
