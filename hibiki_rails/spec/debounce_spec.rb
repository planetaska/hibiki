# frozen_string_literal: true

require "spec_helper"

RSpec.describe Hibiki::Rails::Debounce do
  let(:errors) { [] }
  let(:actor) { Hibiki::Rails::GraphActor.new(on_error: ->(e) { errors << e }) }

  after do
    actor.stop(wait: true)
    expect(errors).to be_empty
  end

  # FIFO barrier — everything posted before this ran once it returns.
  def drain
    barrier = Queue.new
    actor.post { barrier << true }
    raise "actor did not drain within 2s" unless barrier.pop(timeout: 2)
  end

  # Comfortably past the 0.05s debounce wait used below.
  def wait_for_window = sleep 0.1

  def build_debounced_effect(runs)
    state = nil
    actor.post do
      state = Hibiki::State.new(0)
      Hibiki::Effect.new(scheduler: described_class.new(actor:, wait: 0.05)) do
        runs << state.value
      end
    end
    drain
    state
  end

  it "coalesces a burst of invalidations into one trailing run" do
    runs = []
    state = build_debounced_effect(runs)
    expect(runs).to eq([0]) # the initial run is never scheduled (core pin)

    # Three separate writes = three flushes = three scheduler calls, all
    # within one window.
    3.times { actor.post { state.value += 1 } }
    drain
    expect(runs).to eq([0]) # nothing yet: the run waits for the window

    wait_for_window
    drain
    expect(runs).to eq([0, 3]) # one run, seeing then-current state
  end

  it "re-arms after the window: a later burst gets its own run" do
    runs = []
    state = build_debounced_effect(runs)

    actor.post { state.value = 1 }
    wait_for_window
    actor.post { state.value = 2 }
    wait_for_window
    drain

    expect(runs).to eq([0, 1, 2])
  end

  it "drops the deferred run when the effect was disposed meanwhile" do
    runs = []
    effect = nil
    actor.post do
      state = Hibiki::State.new(0)
      effect = Hibiki::Effect.new(scheduler: described_class.new(actor:, wait: 0.05)) do
        runs << state.value
      end
      state.value = 5 # arms the debounce
    end
    actor.post { effect.dispose }
    wait_for_window
    drain

    expect(runs).to eq([0]) # Effect#run no-ops once disposed
  end
end
