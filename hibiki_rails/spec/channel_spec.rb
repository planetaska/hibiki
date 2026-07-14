# frozen_string_literal: true

require "rails_helper"

# The channel under test for the Hibiki::Rails::Channel concern. Class-level
# probes (build_thread, owner, disposed) let examples observe what happened
# on the graph thread; reset in before blocks.
class GraphTestChannel < ActionCable::Channel::Base
  include Hibiki::Rails::Channel

  class << self
    attr_accessor :build_thread, :owner, :disposed
  end

  def build_graph
    self.class.build_thread = Thread.current
    self.class.owner = Hibiki.current_owner

    @count = Hibiki::State.new(0)
    @step = Hibiki::State.new(1)

    Hibiki::Effect.new do
      Turbo::StreamsChannel.broadcast_replace_to(*stream_name, target: "count",
                                                               html: "<p>count #{@count.value}</p>")
    end
    Hibiki::Effect.new do
      Turbo::StreamsChannel.broadcast_replace_to(*stream_name, target: "step",
                                                               html: "<p>step #{@step.value}</p>")
    end

    Hibiki.on_cleanup { self.class.disposed << cid }
  end

  def increment = @count.value += @step.value

  def burst = 10.times { @count.value += 1 }

  def change_step(data) = @step.value = data["step"].to_i

  def boom = raise "graph action failed"
end

class RescuingChannel < ActionCable::Channel::Base
  include Hibiki::Rails::Channel

  rescue_from RuntimeError, with: :note_error

  class << self
    attr_accessor :handled
  end

  def build_graph = nil

  def boom = raise "rescued upstream"

  private

  def note_error(error) = self.class.handled << error.message
end

RSpec.describe GraphTestChannel, type: :channel do
  let(:stream) { "graph_test:c1" }

  before do
    described_class.build_thread = nil
    described_class.owner = nil
    described_class.disposed = []
  end

  # FIFO barrier: everything posted before this has run once it returns.
  def drain
    actor = subscription.instance_variable_get(:@__hibiki_actor)
    barrier = Queue.new
    actor.post { barrier << true }
    raise "graph actor did not drain within 2s" unless barrier.pop(timeout: 2)
  end

  it "rejects a subscription without a cid and drops actions safely" do
    subscribe
    expect(subscription).to be_rejected

    # No actor exists; the perform_action guard must not blow up.
    expect { subscription.perform_action("action" => "increment") }.not_to raise_error
  end

  it "builds the graph once, on its own thread, inside a Hibiki root" do
    expect do
      subscribe(cid: "c1")
      drain
    end.to have_broadcasted_to(stream).with(a_string_including("count 0"))
                                      .and have_broadcasted_to(stream).with(a_string_including("step 1"))

    expect(subscription).to be_confirmed
    expect(described_class.build_thread).not_to be_nil
    expect(described_class.build_thread).not_to eq(Thread.current)
    expect(described_class.owner).to be_a(Hibiki::Root)
  end

  describe "actions" do
    before do
      subscribe(cid: "c1")
      drain
    end

    it "runs the action on the graph thread and re-broadcasts" do
      expect do
        perform :increment
        drain
      end.to have_broadcasted_to(stream).with(a_string_including("count 1")).once
    end

    it "coalesces a burst of writes into one broadcast per affected effect" do
      expect do
        perform :burst
        drain
      end.to have_broadcasted_to(stream).with(a_string_including("count 10")).once
    end

    it "re-runs only the effects whose dependencies changed (fine-grained)" do
      expect do
        perform :change_step, step: 3
        drain
      end.to have_broadcasted_to(stream).with(a_string_including("step 3")).once
    end

    it "keeps the stream_name convention [channel_name, cid]" do
      expect(subscription.send(:stream_name)).to eq(%w[graph_test c1])
    end

    it "routes an unrescued action error to the Rails error reporter" do
      reporter = Class.new do
        def reports = @reports ||= []
        def report(error, **kwargs) = reports << [error, kwargs]
      end.new
      Rails.error.subscribe(reporter)

      perform :boom
      drain

      expect(reporter.reports.size).to eq(1)
      error, kwargs = reporter.reports.first
      expect(error.message).to eq("graph action failed")
      expect(kwargs[:source]).to eq("hibiki_rails")
    ensure
      Rails.error.unsubscribe(reporter)
    end
  end

  describe "unsubscribe" do
    it "disposes the root (cleanups run) and stops the actor" do
      subscribe(cid: "c1")
      drain
      actor = subscription.instance_variable_get(:@__hibiki_actor)

      unsubscribe
      actor.stop(wait: true) # idempotent close + join: drains the posted dispose

      expect(described_class.disposed).to eq(["c1"])
      expect(actor).to be_stopped
    end
  end
end

RSpec.describe RescuingChannel, type: :channel do
  before { described_class.handled = [] }

  it "still applies rescue_from handlers (on the graph thread)" do
    reporter = Class.new do
      def reports = @reports ||= []
      def report(error, **kwargs) = reports << [error, kwargs]
    end.new
    Rails.error.subscribe(reporter)

    subscribe(cid: "c1")
    perform :boom
    actor = subscription.instance_variable_get(:@__hibiki_actor)
    actor.stop(wait: true)

    expect(described_class.handled).to eq(["rescued upstream"])
    expect(reporter.reports).to be_empty
  ensure
    Rails.error.unsubscribe(reporter)
  end
end
