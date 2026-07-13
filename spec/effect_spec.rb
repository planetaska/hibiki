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

  describe "scheduler:" do
    it "hands the re-run to the scheduler instead of running inline" do
      scheduled = []
      seen = []
      a = Hibiki::State.new(1)
      effect = described_class.new(scheduler: ->(e) { scheduled << e }) { seen << a.value }

      a.value = 2
      expect(seen).to eq([1]) # the write did not re-run the block
      expect(scheduled).to eq([effect]) # it was scheduled instead
    end

    it "does not schedule the initial run" do
      scheduled = []
      runs = 0
      described_class.new(scheduler: ->(e) { scheduled << e }) { runs += 1 }

      expect(runs).to eq(1)
      expect(scheduled).to be_empty
    end

    it "schedules once per batch, not once per write" do
      scheduled = []
      a = Hibiki::State.new(1)
      b = Hibiki::State.new(2)
      described_class.new(scheduler: ->(e) { scheduled << e }) { a.value + b.value }

      Hibiki.batch do
        a.value = 10
        b.value = 20
        expect(scheduled).to be_empty # nothing until the flush
      end
      expect(scheduled.size).to eq(1)
    end

    it "schedules once per unbatched write, via the implicit batch" do
      scheduled = []
      a = Hibiki::State.new(1)
      described_class.new(scheduler: ->(e) { scheduled << e }) { a.value }

      a.value = 2
      a.value = 3
      expect(scheduled.size).to eq(2)
    end

    it "re-collects dependencies when the scheduled effect is run" do
      schedules = 0
      pending_effect = nil
      seen = []
      flag = Hibiki::State.new(true)
      a = Hibiki::State.new("a")
      b = Hibiki::State.new("b")
      described_class.new(scheduler: lambda { |e|
        schedules += 1
        pending_effect = e
      }) { seen << (flag.value ? a.value : b.value) }

      flag.value = false
      pending_effect.run
      expect(seen).to eq(%w[a b])

      a.value = "a2" # stale branch after the deferred run: must not schedule
      expect(schedules).to eq(1)

      b.value = "b2" # live branch still does
      expect(schedules).to eq(2)
    end

    it "run is a no-op once disposed (a late debounced run loses to dispose)" do
      runs = 0
      a = Hibiki::State.new(1)
      pending_effect = nil
      effect = described_class.new(scheduler: ->(e) { pending_effect = e }) do
        runs += 1
        a.value
      end

      a.value = 2
      effect.dispose
      pending_effect.run
      expect(runs).to eq(1)
    end

    it "routes a raising scheduler through the flush's error isolation" do
      seen = []
      a = Hibiki::State.new(1)
      described_class.new(scheduler: ->(_e) { raise "boom" }) { a.value }
      described_class.new { seen << a.value }

      expect { Hibiki.batch { a.value = 2 } }.to raise_error("boom")
      expect(seen).to eq([1, 2]) # the rest of the flush still ran
    end

    it "routes a raising scheduler to Hibiki.error_handler when set" do
      handled = []
      Hibiki.error_handler = ->(error, effect) { handled << [error.message, effect] }

      a = Hibiki::State.new(1)
      effect = described_class.new(scheduler: ->(_e) { raise "boom" }) { a.value }

      expect { a.value = 2 }.not_to raise_error
      expect(handled).to eq([["boom", effect]])
    ensure
      Hibiki.error_handler = nil
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
