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
    # Glitch freedom: every unbatched write is an implicit batch of one
    # (Solid's runUpdates), so the whole invalidation wave lands before the
    # effect flushes — it runs once and reads both branches fresh.
    it "runs the effect exactly once, glitch-free, on an unbatched write" do
      log = []
      s = state(1)
      d1 = derived { s.value + 1 }
      d2 = derived { s.value * 10 }
      effect { log << [d1.value, d2.value] }

      expect(log).to eq([[2, 10]])

      s.value = 2
      expect(log).to eq([[2, 10], [3, 20]]) # no [3, 10] glitch in between
    end

    it "stays glitch-free when the branches have uneven depth" do
      # s -> d1 -> effect, s -> d2 -> d3 -> effect: the longer branch must
      # not lag a notification wave behind the shorter one.
      log = []
      s = state(1)
      d1 = derived { s.value + 1 }
      d2 = derived { s.value * 10 }
      d3 = derived { d2.value + 100 }
      effect { log << [d1.value, d3.value] }

      s.value = 2
      expect(log).to eq([[2, 110], [3, 120]])
    end

    it "runs the effect exactly once, glitch-free, when the write is batched" do
      # Same guarantee under an explicit batch: both branches go dirty inside
      # the batch, and the single flush run reads them fresh.
      log = []
      s = state(1)
      d1 = derived { s.value + 1 }
      d2 = derived { s.value * 10 }
      effect { log << [d1.value, d2.value] }

      batch { s.value = 2 }
      expect(log).to eq([[2, 10], [3, 20]])
    end
  end

  describe "diamond graphs through a Reactive class" do
    it "keeps the same glitch-free guarantee when the graph lives in an instance" do
      klass = Class.new do
        include Hibiki::Reactive

        state :root, 1
        derived(:left)  { root + 1 }
        derived(:right) { root * 10 }
        derived(:sum)   { left + right }
      end
      obj = klass.new
      log = []
      effect { log << obj.sum }

      obj.root = 2
      expect(log).to eq([12, 23]) # never a half-updated 13 or 22
    end
  end

  describe "the equality gate" do
    it "runs the effect when one diamond leg changed and the other did not" do
      log = []
      s = state(2)
      changing = derived { s.value * 10 }
      constant = derived { s.value.positive? }
      effect { log << [changing.value, constant.value] }

      s.value = 3
      expect(log).to eq([[20, true], [30, true]])
    end

    it "skips the effect when every leg recomputes to an == value" do
      log = []
      s = state(2)
      d1 = derived { s.value.positive? }
      d2 = derived { s.value.zero? }
      effect { log << [d1.value, d2.value] }

      s.value = 3 # both legs unchanged: nothing for the effect to do
      expect(log).to eq([[true, false]])
    end

    it "re-collects a derived's dependencies even when the gate skips the effect" do
      # Invariant 3 under the gate: validation goes through recompute, so a
      # derived that switches branches to an EQUAL value still moves its
      # subscriptions — the old branch goes quiet, the new one bites.
      runs = 0
      flag = state(true)
      a = state("X")
      b = state("X")
      picked = derived { flag.value ? a.value : b.value }
      effect do
        runs += 1
        picked.value
      end

      flag.value = false # picked: "X" -> "X", so the effect is skipped
      expect(runs).to eq(1)

      a.value = "A2" # stale branch: no notification reaches anyone
      expect(runs).to eq(1)

      b.value = "B2" # live branch, and a real change
      expect(runs).to eq(2)
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
