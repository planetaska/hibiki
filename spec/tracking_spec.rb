# frozen_string_literal: true

RSpec.describe "Hibiki.untrack" do
  it "reads inside untrack do not subscribe the surrounding effect" do
    count = Hibiki::State.new(0)
    runs = 0
    Hibiki::Effect.new do
      runs += 1
      Hibiki.untrack { count.value }
    end

    count.value = 1
    expect(runs).to eq(1) # never re-ran: the read registered nothing
  end

  it "restores the outer observer when the block exits" do
    tracked = Hibiki::State.new(0)
    untracked = Hibiki::State.new(0)
    runs = 0
    Hibiki::Effect.new do
      runs += 1
      Hibiki.untrack { untracked.value }
      tracked.value # after untrack: must register again
    end

    untracked.value = 1
    expect(runs).to eq(1)
    tracked.value = 1
    expect(runs).to eq(2)
  end

  it "returns the block's value" do
    expect(Hibiki.untrack { 42 }).to eq(42)
  end

  it "suppresses only the listener: effects created under untrack are still adopted" do
    toggle = Hibiki::State.new(0)
    child = nil
    Hibiki::Effect.new do
      toggle.value
      Hibiki.untrack { child = Hibiki::Effect.new { nil } }
    end

    first_child = child
    toggle.value = 1 # owner re-runs -> previous generation disposed
    expect(first_child).to be_disposed
  end
end

RSpec.describe "Hibiki.on_cleanup" do
  it "runs the cleanup before the effect re-runs" do
    order = []
    dep = Hibiki::State.new(0)
    Hibiki::Effect.new do
      dep.value
      order << :run
      Hibiki.on_cleanup { order << :cleanup }
    end

    dep.value = 1
    expect(order).to eq(%i[run cleanup run])
  end

  it "runs the cleanup when the effect is disposed" do
    cleaned = false
    effect = Hibiki::Effect.new { Hibiki.on_cleanup { cleaned = true } }

    effect.dispose
    expect(cleaned).to be(true)
  end

  it "runs each registered cleanup exactly once" do
    calls = 0
    dep = Hibiki::State.new(0)
    effect = Hibiki::Effect.new do
      dep.value
      Hibiki.on_cleanup { calls += 1 }
    end

    dep.value = 1 # first generation's cleanup runs
    effect.dispose # second generation's cleanup runs
    effect.dispose # idempotent: nothing left to run
    expect(calls).to eq(2)
  end

  it "runs cleanups in LIFO order" do
    order = []
    effect = Hibiki::Effect.new do
      Hibiki.on_cleanup { order << :first }
      Hibiki.on_cleanup { order << :second }
    end

    effect.dispose
    expect(order).to eq(%i[second first])
  end

  it "runs a child effect's cleanup before the owner's when the owner re-runs" do
    order = []
    dep = Hibiki::State.new(0)
    Hibiki::Effect.new do
      dep.value
      Hibiki.on_cleanup { order << :owner }
      Hibiki::Effect.new { Hibiki.on_cleanup { order << :child } }
    end

    dep.value = 1
    expect(order).to eq(%i[child owner])
  end

  it "registers on the owner, not the listener: a derived computing mid-effect does not capture it" do
    # Parallel to effect adoption through a derived: the cleanup belongs to
    # the running effect, not to the lazy derived whose block registered it.
    cleaned = false
    maker = Hibiki::Derived.new { Hibiki.on_cleanup { cleaned = true } }
    effect = Hibiki::Effect.new { maker.value }

    effect.dispose
    expect(cleaned).to be(true)
  end

  it "still registers under untrack (only the listener is suppressed)" do
    cleaned = false
    effect = Hibiki::Effect.new do
      Hibiki.untrack { Hibiki.on_cleanup { cleaned = true } }
    end

    effect.dispose
    expect(cleaned).to be(true)
  end

  it "warns and never runs the block outside any owner" do
    calls = 0
    expect { Hibiki.on_cleanup { calls += 1 } }.to output(/never run/).to_stderr

    expect(calls).to eq(0)
  end
end
