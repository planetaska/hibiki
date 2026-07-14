# frozen_string_literal: true

require "rails_helper"

# Pins the spec harness itself: the inline dummy app boots, channel specs
# run against the test cable adapter, and turbo-rails broadcasts (including
# partial rendering through ApplicationController) are observable with
# have_broadcasted_to.
class HarnessChannel < ActionCable::Channel::Base
  def subscribed = stream_from("harness")
end

RSpec.describe HarnessChannel, type: :channel do
  it "subscribes and observes plain cable broadcasts" do
    subscribe
    expect(subscription).to be_confirmed

    expect { ActionCable.server.broadcast("harness", { hello: "world" }) }
      .to have_broadcasted_to("harness").with(hello: "world")
  end

  it "observes turbo-rails broadcasts rendered from a partial" do
    expect do
      Turbo::StreamsChannel.broadcast_replace_to(
        "harness", "cid-1",
        target: "greeting", partial: "harness/greeting", locals: { name: "hibiki" }
      )
    end.to have_broadcasted_to("harness:cid-1").with(a_string_including("Hello, hibiki"))
  end
end
