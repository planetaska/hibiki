# frozen_string_literal: true

RSpec.describe Hibiki::Effect do
  it "runs immediately on creation" do
    runs = 0
    described_class.new { runs += 1 }

    expect(runs).to eq(1)
  end

  it "re-runs when a dependency changes" do
    runs = 0
    name = Hibiki::State.new("world")
    described_class.new do
      runs += 1
      name.value
    end

    name.value = "ruby"
    expect(runs).to eq(2)
  end

  it "does not re-run when a dependency is written an == value" do
    runs = 0
    name = Hibiki::State.new("world")
    described_class.new do
      runs += 1
      name.value
    end

    name.value = "world".dup
    expect(runs).to eq(1)
  end

  it "re-runs when a derived dependency changes (state -> derived -> effect)" do
    seen = []
    count = Hibiki::State.new(1)
    doubled = Hibiki::Derived.new { count.value * 2 }
    described_class.new { seen << doubled.value }

    count.value = 3
    expect(seen).to eq([2, 6])
  end

  describe "#dispose" do
    it "stops future re-runs" do
      runs = 0
      count = Hibiki::State.new(0)
      effect = described_class.new do
        runs += 1
        count.value
      end

      effect.dispose
      count.value = 1
      expect(runs).to eq(1)
      expect(effect).to be_disposed
    end

    it "is idempotent" do
      effect = described_class.new { nil }

      effect.dispose
      expect { effect.dispose }.not_to raise_error
    end

    it "wins over a pending batch flush" do
      runs = 0
      count = Hibiki::State.new(0)
      effect = described_class.new do
        runs += 1
        count.value
      end

      Hibiki.batch do
        count.value = 1 # queues the effect...
        effect.dispose  # ...but disposal before the flush must stick
      end
      expect(runs).to eq(1)
    end
  end

  describe "ownership" do
    it "disposes an inner effect when the outer effect re-runs" do
      inner_runs = 0
      outer = Hibiki::State.new(0)
      inner = Hibiki::State.new(0)
      described_class.new do
        outer.value
        described_class.new do
          inner_runs += 1
          inner.value
        end
      end
      expect(inner_runs).to eq(1)

      inner.value = 1 # current inner generation re-runs
      expect(inner_runs).to eq(2)

      outer.value = 1 # outer re-runs: old inner disposed, new one created
      expect(inner_runs).to eq(3)

      inner.value = 2 # only the new generation re-runs — no leak
      expect(inner_runs).to eq(4)
    end

    it "disposes inner effects when the outer effect is disposed" do
      inner_runs = 0
      dep = Hibiki::State.new(0)
      effect = described_class.new do
        described_class.new do
          inner_runs += 1
          dep.value
        end
      end

      effect.dispose
      dep.value = 1
      expect(inner_runs).to eq(1)
    end

    it "assigns ownership through a derived to the running effect" do
      # A lazy derived recomputing mid-effect must not steal ownership:
      # the effect its block creates belongs to the running effect.
      inner_runs = 0
      dep = Hibiki::State.new(0)
      maker = Hibiki::Derived.new do
        described_class.new do
          inner_runs += 1
          dep.value
        end
      end
      effect = described_class.new { maker.value }

      effect.dispose
      dep.value = 1
      expect(inner_runs).to eq(1)
    end
  end
end
