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

  describe "the equality gate" do
    # Svelte's $derived compares, and so does Hibiki — on the reading effect's
    # side, at the batch flush, because Derived#invalidate has already notified
    # downstream by the time it knows its new value.
    it "does not re-run when a derived recomputes to an == value" do
      runs = 0
      count = Hibiki::State.new(1)
      parity = Hibiki::Derived.new { count.value.even? }
      described_class.new do
        runs += 1
        parity.value
      end

      count.value = 3 # invalidates parity, whose value is still false
      expect(runs).to eq(1)
    end

    it "re-runs when the derived's value really does change" do
      seen = []
      count = Hibiki::State.new(1)
      parity = Hibiki::Derived.new { count.value.even? }
      described_class.new { seen << parity.value }

      count.value = 2
      expect(seen).to eq([false, true])
    end

    it "leaves the subscription intact across a suppressed run" do
      # A skipped run must not look like a disposal: the next real change still
      # has to arrive.
      seen = []
      count = Hibiki::State.new(1)
      parity = Hibiki::Derived.new { count.value.even? }
      described_class.new { seen << parity.value }

      count.value = 3 # suppressed
      count.value = 4 # must still land
      expect(seen).to eq([false, true])
    end

    it "runs when one of several sources changed and the others did not" do
      seen = []
      count = Hibiki::State.new(1)
      label = Hibiki::State.new("a")
      parity = Hibiki::Derived.new { count.value.even? }
      described_class.new { seen << [parity.value, label.value] }

      label.value = "b" # parity unchanged, but label is a source too
      expect(seen).to eq([[false, "a"], [false, "b"]])
    end

    # The two-gate trap from the AR exploration (ar-equality-notes.md): == is
    # asked at the write AND here at the flush. A comparator honored only on
    # write would notify, then have the flush compare fresh-vs-seen with ==
    # ("same row, unchanged") and skip the rerun anyway. This spec goes red if
    # changed_from? stops consulting @equals.
    it "re-runs through a batch flush when the comparator sees a change == cannot" do
      record_class = Struct.new(:id, :name) do
        def ==(other) = self.class == other.class && id == other.id
      end
      seen = []
      row = Hibiki::State.new(record_class.new(1, "draft"), equals: ->(a, b) { a.name == b.name })
      described_class.new { seen << row.value.name }

      Hibiki.batch { row.value = record_class.new(1, "published") }
      expect(seen).to eq(%w[draft published])
    end

    it "honors a derived's equals: (a recompute within tolerance is no change)" do
      runs = 0
      raw = Hibiki::State.new(1.0)
      smoothed = Hibiki::Derived.new(equals: ->(a, b) { (a - b).abs < 0.01 }) { raw.value }
      described_class.new do
        runs += 1
        smoothed.value
      end

      raw.value = 1.001 # recomputes, but the derived calls it unchanged
      expect(runs).to eq(1)
      raw.value = 2.0 # beyond tolerance — still compared against 1.0, the last value read
      expect(runs).to eq(2)
    end

    it "swallows an update from a derived that returns the object it mutated" do
      # Svelte's documented caveat, and ours: == on the same object is true, so
      # the gate cannot see an in-place mutation. Pinned as intended behaviour.
      items = []
      version = Hibiki::State.new(0)
      list = Hibiki::Derived.new do
        version.value
        items
      end
      seen = []
      described_class.new { seen << list.value.size }

      items << :new
      version.value = 1
      expect(seen).to eq([0])
    end
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

    it "is not called at all when nothing the effect read changed" do
      # What makes a debounce mitigation unnecessary rather than merely cheaper:
      # a no-op wave never reaches the scheduler, so nothing is queued to fire.
      scheduled = []
      count = Hibiki::State.new(1)
      parity = Hibiki::Derived.new { count.value.even? }
      described_class.new(scheduler: ->(e) { scheduled << e }) { parity.value }

      count.value = 3
      expect(scheduled).to be_empty
      count.value = 2 # a real change still schedules
      expect(scheduled.size).to eq(1)
    end

    it "run is ungated: when the scheduler says run, it runs" do
      runs = 0
      count = Hibiki::State.new(1)
      parity = Hibiki::Derived.new { count.value.even? }
      effect = described_class.new do
        runs += 1
        parity.value
      end

      effect.run
      expect(runs).to eq(2)
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
