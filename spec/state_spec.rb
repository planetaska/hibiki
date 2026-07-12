# frozen_string_literal: true

RSpec.describe Hibiki::State do
  # A bare observer: whatever is on the observer stack during a read
  # subscribes to the signal, exactly like a Derived or Effect would.
  # (`add_source` is the reverse edge every subscription now records.)
  let(:observer) { instance_double(Hibiki::Effect, invalidate: nil, add_source: nil) }

  it "returns its initial value" do
    expect(described_class.new(1).value).to eq(1)
  end

  it "returns the written value" do
    counter = described_class.new(0)
    counter.value = 5
    expect(counter.value).to eq(5)
  end

  it "notifies subscribers on write" do
    counter = described_class.new(0)
    Hibiki.track(observer) { counter.value }

    expect(observer).to receive(:invalidate)
    counter.value = 1
  end

  it "does not notify when written an == value" do
    name = described_class.new("ruby")
    Hibiki.track(observer) { name.value }

    expect(observer).not_to receive(:invalidate)
    name.value = "ruby".dup # equal but not the same object
  end

  it "does not subscribe readers outside a tracking window" do
    counter = described_class.new(0)
    counter.value # plain read, nobody on the observer stack

    expect(observer).not_to receive(:invalidate)
    counter.value = 1
  end

  describe "#peek" do
    it "returns the current value without subscribing" do
      counter = described_class.new(0)
      Hibiki.track(observer) { expect(counter.peek).to eq(0) }

      expect(observer).not_to receive(:invalidate)
      counter.value = 1
    end

    it "lets an effect read-modify-write without looping on itself" do
      count = Hibiki::State.new(1)
      history = described_class.new([])
      Hibiki::Effect.new { history.value = history.peek + [count.value] }

      count.value = 2
      expect(history.peek).to eq([1, 2]) # and no infinite self-trigger
    end
  end

  describe "#call" do
    it "reads like #value, registering a dependency" do
      counter = described_class.new(3)
      Hibiki.track(observer) { expect(counter.call).to eq(3) }

      expect(observer).to receive(:invalidate)
      counter.value = 4
    end
  end

  describe "#update" do
    it "writes the block's result over the current value" do
      counter = described_class.new(1)
      counter.update { it + 1 }
      expect(counter.value).to eq(2)
    end

    it "notifies subscribers like a plain write" do
      counter = described_class.new(0)
      Hibiki.track(observer) { counter.value }

      expect(observer).to receive(:invalidate)
      counter.update { it + 1 }
    end
  end
end
