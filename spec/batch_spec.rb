# frozen_string_literal: true

RSpec.describe "Hibiki.batch" do
  it "coalesces multiple writes into a single effect run" do
    runs = 0
    sum = nil
    a = Hibiki::State.new(1)
    b = Hibiki::State.new(2)
    Hibiki::Effect.new do
      runs += 1
      sum = a.value + b.value
    end

    Hibiki.batch do
      a.value = 10
      b.value = 20
    end

    expect(runs).to eq(2) # initial run + one flush
    expect(sum).to eq(30)
  end

  it "returns the block's value" do
    expect(Hibiki.batch { :done }).to eq(:done)
  end

  it "applies writes immediately inside the block (only effects are deferred)" do
    a = Hibiki::State.new(1)
    doubled = Hibiki::Derived.new { a.value * 2 }

    Hibiki.batch do
      a.value = 5
      expect(a.value).to eq(5)
      expect(doubled.value).to eq(10)
    end
  end

  it "flushes once, at the end of the outermost batch, when batches nest" do
    runs = 0
    a = Hibiki::State.new(1)
    Hibiki::Effect.new do
      runs += 1
      a.value
    end

    Hibiki.batch do
      a.value = 2
      Hibiki.batch { a.value = 3 }
      expect(runs).to eq(1) # inner exit must not flush
    end

    expect(runs).to eq(2)
  end

  it "does not re-run an effect when a batched write is an == value" do
    runs = 0
    a = Hibiki::State.new(1)
    Hibiki::Effect.new do
      runs += 1
      a.value
    end

    Hibiki.batch { a.value = 1 }
    expect(runs).to eq(1)
  end

  # The one deliberate change these semantics took in 0.2.0 (Phase 1.75): the
  # equality gate compares what an effect last READ, so a batch that cancels
  # itself out leaves it nothing to do. Each write here is a genuine change —
  # it is the net result that is not.
  it "does not re-run an effect when a batch nets to no change" do
    runs = 0
    a = Hibiki::State.new(1)
    Hibiki::Effect.new do
      runs += 1
      a.value
    end

    Hibiki.batch do
      a.value = 2
      a.value = 1
    end

    expect(runs).to eq(1)
  end

  it "never lets the effect observe intermediate values" do
    seen = []
    a = Hibiki::State.new(1)
    Hibiki::Effect.new { seen << a.value }

    Hibiki.batch do
      a.value = 2
      a.value = 3
    end

    expect(seen).to eq([1, 3])
  end

  it "still flushes effects for applied writes when the block raises" do
    seen = []
    a = Hibiki::State.new(1)
    Hibiki::Effect.new { seen << a.value }

    expect do
      Hibiki.batch do
        a.value = 2
        raise "boom"
      end
    end.to raise_error("boom")

    expect(seen).to eq([1, 2])
  end

  describe "error isolation in the flush" do
    it "still runs the remaining pending effects when one raises, then re-raises" do
      seen = []
      a = Hibiki::State.new(1)
      Hibiki::Effect.new { raise "boom" if a.value > 1 }
      Hibiki::Effect.new { seen << a.value }

      expect { Hibiki.batch { a.value = 2 } }.to raise_error("boom")
      expect(seen).to eq([1, 2]) # the raise must not drop the second effect
    end

    it "re-raises the first error when several effects raise" do
      seen = []
      a = Hibiki::State.new(1)
      Hibiki::Effect.new { raise "first" if a.value > 1 }
      Hibiki::Effect.new { seen << a.value }
      Hibiki::Effect.new { raise "second" if a.value > 1 }

      expect { Hibiki.batch { a.value = 2 } }.to raise_error("first")
      expect(seen).to eq([1, 2])
    end

    it "isolates eager (unbatched) writes too, via the implicit batch" do
      seen = []
      a = Hibiki::State.new(1)
      Hibiki::Effect.new { raise "boom" if a.value > 1 }
      Hibiki::Effect.new { seen << a.value }

      expect { a.value = 2 }.to raise_error("boom")
      expect(seen).to eq([1, 2])
    end

    context "with Hibiki.error_handler set" do
      after { Hibiki.error_handler = nil }

      it "routes each error to the handler instead of raising" do
        handled = []
        Hibiki.error_handler = ->(error, effect) { handled << [error.message, effect] }

        seen = []
        a = Hibiki::State.new(1)
        raiser = Hibiki::Effect.new { raise "boom" if a.value > 1 }
        Hibiki::Effect.new { seen << a.value }

        expect { Hibiki.batch { a.value = 2 } }.not_to raise_error
        expect(seen).to eq([1, 2])
        expect(handled).to eq([["boom", raiser]])
      end

      it "completes the flush across multiple failing effects" do
        handled = []
        Hibiki.error_handler = ->(error, _effect) { handled << error.message }

        seen = []
        a = Hibiki::State.new(1)
        Hibiki::Effect.new { raise "first" if a.value > 1 }
        Hibiki::Effect.new { seen << a.value }
        Hibiki::Effect.new { raise "second" if a.value > 1 }

        expect { Hibiki.batch { a.value = 2 } }.not_to raise_error
        expect(seen).to eq([1, 2])
        expect(handled).to eq(%w[first second])
      end
    end
  end

  it "runs an effect created inside a batch immediately, as usual" do
    runs = 0
    Hibiki.batch { Hibiki::Effect.new { runs += 1 } }

    expect(runs).to eq(1)
  end

  it "leaves writes outside a batch eager" do
    runs = 0
    a = Hibiki::State.new(1)
    Hibiki::Effect.new do
      runs += 1
      a.value
    end

    Hibiki.batch { a.value = 2 }
    a.value = 3
    a.value = 4
    expect(runs).to eq(4) # initial + flush + two eager reruns
  end
end
