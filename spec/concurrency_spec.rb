# frozen_string_literal: true

# Pins the isolation model (see "Threading model" in the README): tracking
# bookkeeping is per-execution-context, while a signal graph itself is
# confined to the context that uses it. Queues sequence the threads below so
# every cross-thread step is deterministic, never sleep-based.
RSpec.describe "concurrency isolation" do
  it "does not subscribe another thread's reads to an in-flight observer" do
    signal = Hibiki::State.new(0)
    other = Hibiki::State.new(0)
    effect_runs = 0

    reading = Queue.new
    read_done = Queue.new
    # Created OUTSIDE any tracking window: its reads must never register,
    # even while the main thread's effect is mid-run.
    reader = Thread.new do
      reading.pop
      other.value
      read_done << true
    end

    Hibiki::Effect.new do
      effect_runs += 1
      signal.value
      if effect_runs == 1
        reading << true
        read_done.pop
      end
    end

    # If the reader's read had leaked onto this effect, this write would
    # re-run it.
    other.value = 1
    expect(effect_runs).to eq(1)
  ensure
    reader&.join
  end

  it "does not adopt another thread's effects into an in-flight owner" do
    trigger = Hibiki::State.new(0)
    inner_signal = Hibiki::State.new(0)
    inner_runs = 0
    outer_runs = 0

    creating = Queue.new
    created = Queue.new
    creator = Thread.new do
      creating.pop
      Hibiki::Effect.new do
        inner_runs += 1
        inner_signal.value
      end
      created << true
    end

    Hibiki::Effect.new do
      outer_runs += 1
      trigger.value
      if outer_runs == 1
        creating << true
        created.pop
      end
    end

    # Re-running the outer effect disposes its children. The thread's effect
    # is not its child, so it must survive and keep reacting.
    trigger.value = 1
    inner_signal.value = 1
    expect(inner_runs).to eq(2)
  ensure
    creator&.join
  end

  it "does not defer another thread's effects while a batch is open" do
    runs_after_write = nil

    batching = Queue.new
    wrote = Queue.new
    writer = Thread.new do
      signal = Hibiki::State.new(0)
      runs = 0
      Hibiki::Effect.new do
        runs += 1
        signal.value
      end
      batching.pop
      # The main thread is mid-batch; this thread is not. Its write must run
      # its effect eagerly, not park it in someone else's pending queue.
      signal.value = 1
      runs_after_write = runs
      wrote << true
    end

    unrelated = Hibiki::State.new(0)
    Hibiki.batch do
      unrelated.value = 1
      batching << true
      wrote.pop
    end

    expect(runs_after_write).to eq(2)
  ensure
    writer&.join
  end

  # Pins the Fiber[] choice for the observer: Enumerator#next runs its block
  # in an internal fiber, and Fiber storage is inherited at fiber creation, so
  # reads in there still see the tracking window. Fiber-local-but-uninherited
  # storage (Thread.current[]) would silently drop this dependency.
  it "tracks reads made through an Enumerator's internal fiber" do
    signal = Hibiki::State.new(1)
    doubled = Hibiki::Derived.new do
      Enumerator.new { |y| y << (signal.value * 2) }.next
    end

    expect(doubled.value).to eq(2)
    signal.value = 5
    expect(doubled.value).to eq(10)
  end

  # Signals are unshareable objects, so a graph can never cross a Ractor
  # boundary — Ractor support means each Ractor runs its own independent
  # reactive world. Module-ivar state used to raise IsolationError here.
  it "runs a full reactive cycle inside a non-main Ractor" do
    prev = Warning[:experimental]
    Warning[:experimental] = false

    ractor = Ractor.new do
      log = []
      count = Hibiki::State.new(1)
      doubled = Hibiki::Derived.new { count.value * 2 }
      Hibiki::Effect.new { log << doubled.value }
      Hibiki.batch { count.value = 3 }
      log
    end

    # Ractor#value arrived with the 3.5 Port redesign; 3.4 (our floor) takes.
    result = ractor.respond_to?(:value) ? ractor.value : ractor.take
    expect(result).to eq([2, 6])
  ensure
    Warning[:experimental] = prev
  end
end
