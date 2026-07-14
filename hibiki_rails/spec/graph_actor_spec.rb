# frozen_string_literal: true

require "spec_helper"

RSpec.describe Hibiki::Rails::GraphActor do
  def build_actor(**) = described_class.new(on_error: ->(e) { raise e }, **)

  it "runs posted jobs in FIFO order on a single thread" do
    actor = build_actor
    order = []
    threads = []

    actor.post { order << 1 }
    actor.post { order << 2 }
    actor.post { threads << Thread.current }
    actor.post { threads << Thread.current }
    actor.stop(wait: true)

    expect(order).to eq([1, 2])
    expect(threads.uniq.size).to eq(1)
    expect(threads.first).not_to eq(Thread.current)
  end

  it "names the worker thread" do
    actor = described_class.new(name: "hibiki-spec", on_error: ->(e) { raise e })
    name = nil
    actor.post { name = Thread.current.name }
    actor.stop(wait: true)

    expect(name).to eq("hibiki-spec")
  end

  describe "error isolation" do
    it "routes a job's error to on_error and keeps the worker alive" do
      errors = []
      actor = described_class.new(on_error: ->(e) { errors << e })
      after = false

      actor.post { raise "boom" }
      actor.post { after = true }
      actor.stop(wait: true)

      expect(errors.map(&:message)).to eq(["boom"])
      expect(after).to be(true)
    end

    it "lets non-StandardError take the worker down" do
      Thread.report_on_exception = false # keep the expected crash off stderr
      errors = []
      actor = described_class.new(on_error: ->(e) { errors << e })

      actor.post { raise NotImplementedError, "not rescued" }
      # Joining the dead worker re-raises what killed it.
      expect { actor.stop(wait: true) }.to raise_error(NotImplementedError)
      expect(errors).to be_empty
    ensure
      Thread.report_on_exception = true
    end
  end

  describe "#stop" do
    it "drains jobs posted before the stop" do
      actor = build_actor
      drained = false

      actor.post { sleep 0.01 } # keep the worker busy so the queue backs up
      actor.post { drained = true }
      actor.stop(wait: true)

      expect(drained).to be(true)
    end

    it "is idempotent" do
      actor = build_actor
      actor.stop(wait: true)

      expect { actor.stop }.not_to raise_error
      expect(actor).to be_stopped
    end
  end

  describe "#post after stop" do
    it "returns false and never runs the job (teardown race, must not raise)" do
      actor = build_actor
      actor.stop(wait: true)
      ran = false

      expect(actor.post { ran = true }).to be(false)
      expect(ran).to be(false)
    end

    it "returns true while running" do
      actor = build_actor

      expect(actor.post { nil }).to be(true)
      actor.stop(wait: true)
    end
  end
end
