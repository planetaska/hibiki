# frozen_string_literal: true

require "rails_helper"

class RegistryTestChannel < ActionCable::Channel::Base
  include Hibiki::Rails::Channel

  def build_graph = nil
end

RSpec.describe Hibiki::Rails::Registry do
  describe "#dispose_all" do
    it "closes each distinct connection once, however many channels share it" do
      registry = described_class.new
      shared = double("connection", close: nil)
      other = double("connection", close: nil)
      registry.register(double("channel a", connection: shared))
      registry.register(double("channel b", connection: shared))
      registry.register(double("channel c", connection: other))

      registry.dispose_all

      expect(shared).to have_received(:close).once
      expect(other).to have_received(:close).once
    end
  end
end

RSpec.describe RegistryTestChannel, type: :channel do
  it "registers on subscribe and unregisters on unsubscribe" do
    expect { subscribe(cid: "c1") }.to change { Hibiki::Rails.registry.size }.by(1)
    expect { unsubscribe }.to change { Hibiki::Rails.registry.size }.by(-1)
  end

  it "does not register a rejected subscription" do
    expect { subscribe }.not_to(change { Hibiki::Rails.registry.size })
    expect(subscription).to be_rejected
  end
end

RSpec.describe Hibiki::Rails::Railtie do
  it "wires dispose_all into the Rails reloader (to_prepare)" do
    connection = double("connection", close: nil)
    channel = double("channel", connection:)
    Hibiki::Rails.registry.register(channel)

    # Runs every to_prepare block the dummy app collected at boot —
    # exactly what a dev-mode code reload triggers. NOTE: the callback
    # lives on the app's own reloader (an anonymous ActiveSupport::Reloader
    # subclass), not on ActiveSupport::Reloader itself.
    Rails.application.reloader.prepare!

    expect(connection).to have_received(:close).once
  ensure
    Hibiki::Rails.registry.unregister(channel)
  end
end
