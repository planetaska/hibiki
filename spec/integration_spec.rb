# frozen_string_literal: true

# Graph-shaped scenarios across State/Derived/Effect, written with the DSL
# (which doubles as its coverage).
RSpec.describe "reactive graphs" do
  include Hibiki::DSL

  describe "dynamic dependencies (flag ? a : b)" do
    # The reason tracking is runtime, not static: deps are re-collected on
    # every recompute, so conditional reads switch subscriptions.
    it "ignores writes to the branch it is not currently reading" do
      runs = 0
      flag = state(true)
      a = state("A")
      b = state("B")
      picked = derived do
        runs += 1
        flag.value ? a.value : b.value
      end

      expect(picked.value).to eq("A")
      b.value = "B2" # not a dependency right now
      expect(picked.value).to eq("A")
      expect(runs).to eq(1) # no recompute happened

      flag.value = false
      expect(picked.value).to eq("B2") # deps re-collected
    end

    it "does not recompute when a stale dependency changes" do
      # Roadmap #1: recomputing does not yet unsubscribe from old deps
      # (Solid clears per-observer dep lists before each rerun). After the
      # flip, `picked` no longer reads `a`, but it is still subscribed, so
      # writing `a` spuriously invalidates it.
      pending "stale subscriptions: old deps are never unsubscribed (roadmap #1)"

      runs = 0
      flag = state(true)
      a = state("A")
      b = state("B")
      picked = derived do
        runs += 1
        flag.value ? a.value : b.value
      end

      picked.value          # deps: flag, a
      flag.value = false
      picked.value          # deps re-collected: flag, b
      runs_after_flip = runs

      a.value = "A2"        # no longer a dependency — should be a no-op
      picked.value
      expect(runs).to eq(runs_after_flip)
    end
  end

  describe "chained deriveds" do
    it "flows updates through the whole chain" do
      x = state(1)
      y = derived { x.value + 1 }
      doubled = derived { y.value * 2 }

      expect(doubled.value).to eq(4)
      x.value = 10
      expect(y.value).to eq(11)
      expect(doubled.value).to eq(22)
    end
  end

  describe "diamond graphs (s -> d1, d2 -> effect)" do
    # Roadmap #3: no glitch freedom yet. Notifying s's subscribers one at a
    # time means the effect re-runs once per branch, and the first re-run
    # reads d1 fresh but d2 stale. This spec pins the CURRENT behavior so
    # the fix (topological ordering / batching) shows up as a diff here.
    it "runs the effect once per branch, glitching on the first run" do
      log = []
      s = state(1)
      d1 = derived { s.value + 1 }
      d2 = derived { s.value * 10 }
      effect { log << [d1.value, d2.value] }

      expect(log).to eq([[2, 10]])

      s.value = 2
      expect(log).to eq([
                          [2, 10], # initial run
                          [3, 10], # glitch: d1 fresh, d2 still cached
                          [3, 20]  # consistent again
                        ])
    end
  end

  describe "effects on derived state" do
    it "sees consistent values through a linear chain" do
      seen = []
      x = state(1)
      y = derived { x.value + 1 }
      effect { seen << y.value }

      x.value = 2
      x.value = 2 # == write: no-op end to end
      x.value = 5
      expect(seen).to eq([2, 3, 6])
    end
  end
end
