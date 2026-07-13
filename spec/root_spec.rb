# frozen_string_literal: true

RSpec.describe Hibiki::Root do
  it "yields the root to the block and returns it" do
    yielded = nil
    root = Hibiki.root { |r| yielded = r }

    expect(root).to be_a(described_class)
    expect(yielded).to be(root)
  end

  it "disposes effects created inside the block on #dispose" do
    runs = 0
    dep = Hibiki::State.new(0)
    root = Hibiki.root do
      Hibiki::Effect.new do
        runs += 1
        dep.value
      end
    end
    expect(runs).to eq(1)

    dep.value = 1
    expect(runs).to eq(2)

    root.dispose
    dep.value = 2
    expect(runs).to eq(2)
    expect(root).to be_disposed
  end

  it "disposes transitively: effects owned by owned effects go down too" do
    inner_runs = 0
    dep = Hibiki::State.new(0)
    root = Hibiki.root do
      Hibiki::Effect.new do
        Hibiki::Effect.new do
          inner_runs += 1
          dep.value
        end
      end
    end

    root.dispose
    dep.value = 1
    expect(inner_runs).to eq(1)
  end

  it "is idempotent" do
    root = Hibiki.root { nil }

    root.dispose
    expect { root.dispose }.not_to raise_error
  end

  it "runs the block untracked: reads inside do not subscribe an enclosing effect" do
    count = Hibiki::State.new(0)
    runs = 0
    Hibiki::Effect.new do
      runs += 1
      Hibiki.root { count.value }
    end

    count.value = 1
    expect(runs).to eq(1) # the read registered nothing
  end

  it "is detached: an enclosing effect's re-run does not dispose it" do
    outer = Hibiki::State.new(0)
    inner = Hibiki::State.new(0)
    inner_runs = 0
    roots = []
    Hibiki::Effect.new do
      outer.value
      roots << Hibiki.root do
        Hibiki::Effect.new do
          inner_runs += 1
          inner.value
        end
      end
    end
    expect(inner_runs).to eq(1)

    outer.value = 1 # effect re-runs, creates a second root; the first survives
    expect(roots.size).to eq(2)
    expect(inner_runs).to eq(2)

    inner.value = 1 # BOTH generations re-run: the first was never disposed
    expect(inner_runs).to eq(4)

    roots.each(&:dispose)
    inner.value = 2
    expect(inner_runs).to eq(4)
  end

  it "runs cleanups registered in the block on dispose, LIFO" do
    order = []
    root = Hibiki.root do
      Hibiki.on_cleanup { order << :first }
      Hibiki.on_cleanup { order << :second }
    end

    root.dispose
    expect(order).to eq(%i[second first])
  end

  it "runs cleanups only once" do
    calls = 0
    root = Hibiki.root { Hibiki.on_cleanup { calls += 1 } }

    root.dispose
    root.dispose
    expect(calls).to eq(1)
  end
end
