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
