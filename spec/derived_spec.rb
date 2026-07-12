# frozen_string_literal: true

RSpec.describe Hibiki::Derived do
  it "is lazy: the block does not run until the first read" do
    runs = 0
    derived = described_class.new { runs += 1 }

    expect(runs).to eq(0)
    derived.value
    expect(runs).to eq(1)
  end

  it "caches: repeated reads do not recompute" do
    runs = 0
    derived = described_class.new { runs += 1 }

    3.times { derived.value }
    expect(runs).to eq(1)
  end

  it "computes from its dependencies" do
    count = Hibiki::State.new(2)
    doubled = described_class.new { count.value * 2 }

    expect(doubled.value).to eq(4)
  end

  it "recomputes on read after a dependency changes" do
    count = Hibiki::State.new(2)
    doubled = described_class.new { count.value * 2 }
    doubled.value

    count.value = 5
    expect(doubled.value).to eq(10)
  end

  it "does not recompute on write, only on read" do
    runs = 0
    count = Hibiki::State.new(0)
    derived = described_class.new do
      runs += 1
      count.value
    end
    derived.value

    count.value = 1
    expect(runs).to eq(1) # invalidated, but not yet recomputed
    derived.value
    expect(runs).to eq(2)
  end

  it "recomputes exactly once per invalidation, however many reads follow" do
    runs = 0
    count = Hibiki::State.new(0)
    derived = described_class.new do
      runs += 1
      count.value
    end
    derived.value

    count.value = 1
    3.times { derived.value }
    expect(runs).to eq(2)
  end

  describe "#peek" do
    it "recomputes when dirty but does not subscribe the reader" do
      count = Hibiki::State.new(2)
      doubled = described_class.new { count.value * 2 }
      runs = 0
      Hibiki::Effect.new do
        runs += 1
        doubled.peek
      end

      count.value = 5
      expect(runs).to eq(1) # effect never depended on doubled
      expect(doubled.peek).to eq(10) # yet peek sees the fresh value
    end
  end

  describe "#call" do
    it "reads like #value, registering a dependency" do
      count = Hibiki::State.new(2)
      doubled = described_class.new { count.value * 2 }
      runs = 0
      Hibiki::Effect.new do
        runs += 1
        doubled.call
      end

      count.value = 5
      expect(runs).to eq(2)
    end
  end

  it "propagates dirtiness through chained deriveds" do
    count = Hibiki::State.new(1)
    inc = described_class.new { count.value + 1 }
    doubled = described_class.new { inc.value * 2 }

    expect(doubled.value).to eq(4)
    count.value = 10
    expect(doubled.value).to eq(22)
  end

  it "stays lazy through a chain: writing the root recomputes nothing" do
    runs = 0
    count = Hibiki::State.new(1)
    inc = described_class.new { count.value + 1 }
    doubled = described_class.new do
      runs += 1
      inc.value * 2
    end
    doubled.value

    count.value = 10
    expect(runs).to eq(1)
  end
end
