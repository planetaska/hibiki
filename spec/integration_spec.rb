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
      # Each recompute clears the observer's source list first (Solid's
      # cleanNode), so after the flip `picked` is unsubscribed from `a` and
      # writing `a` no longer invalidates it.
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

    it "does not re-run an effect when a stale dependency changes" do
      # Same shape as above, but the observer is an Effect: reruns are eager,
      # so a stale subscription would fire the block immediately.
      runs = 0
      flag = state(true)
      a = state("A")
      b = state("B")
      effect do
        runs += 1
        flag.value ? a.value : b.value
      end

      flag.value = false    # deps re-collected: flag, b
      runs_after_flip = runs

      a.value = "A2"        # no longer a dependency — should be a no-op
      expect(runs).to eq(runs_after_flip)
      b.value = "B2"        # still a dependency — must re-run
      expect(runs).to eq(runs_after_flip + 1)
    end

    it "re-subscribes to a branch it returns to" do
      # Guards against over-clearing: severed edges must come back once the
      # branch is read again.
      flag = state(true)
      a = state("A")
      b = state("B")
      picked = derived { flag.value ? a.value : b.value }

      picked.value
      flag.value = false    # a unsubscribed
      picked.value
      flag.value = true     # a is a live dependency again
      picked.value

      a.value = "A2"
      expect(picked.value).to eq("A2")
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

    it "runs the effect exactly once, glitch-free, when the write is batched" do
      # Batching sidesteps the diamond glitch: both branches go dirty inside
      # the batch, and the single flush run reads them fresh. Topological
      # ordering for UNBATCHED writes is still roadmap #2.
      log = []
      s = state(1)
      d1 = derived { s.value + 1 }
      d2 = derived { s.value * 10 }
      effect { log << [d1.value, d2.value] }

      batch { s.value = 2 }
      expect(log).to eq([[2, 10], [3, 20]])
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
