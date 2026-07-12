# frozen_string_literal: true

RSpec.describe Hibiki::Reactive do
  let(:counter_class) do
    Class.new do
      include Hibiki::Reactive

      state :count, 0
      derived(:doubled) { count * 2 }

      def increment = self.count += 1
    end
  end

  it "round-trips reads and writes through plain accessors" do
    counter = counter_class.new
    expect(counter.count).to eq(0)
    counter.count = 5
    expect(counter.count).to eq(5)
  end

  it "keeps signals per-instance" do
    a = counter_class.new
    b = counter_class.new
    a.count = 10
    expect(b.count).to eq(0)
  end

  it "accepts a write before the first read" do
    counter = counter_class.new
    counter.count = 7
    expect(counter.count).to eq(7)
  end

  it "re-runs an external effect when state is written through the writer" do
    counter = counter_class.new
    seen = []
    Hibiki::Effect.new { seen << counter.count }

    counter.increment
    expect(seen).to eq([0, 1])
  end

  it "tracks derived through the reader chain" do
    counter = counter_class.new
    expect(counter.doubled).to eq(0)
    counter.count = 3
    expect(counter.doubled).to eq(6)
  end

  it "keeps derived lazy: writes recompute nothing until a read" do
    runs = 0
    klass = Class.new do
      include Hibiki::Reactive

      state :count, 0
    end
    klass.derived(:tracked) do
      runs += 1
      count
    end

    obj = klass.new
    obj.tracked
    obj.count = 1
    expect(runs).to eq(1) # dirty, not recomputed
    obj.tracked
    expect(runs).to eq(2)
  end

  it "re-collects dynamic dependencies through readers" do
    klass = Class.new do
      include Hibiki::Reactive

      state :flag, true
      state :a, "A"
      state :b, "B"
      derived(:picked) { flag ? a : b }
    end
    obj = klass.new
    runs = 0
    Hibiki::Effect.new do
      runs += 1
      obj.picked
    end

    obj.b = "B2" # not a dependency right now
    expect(runs).to eq(1)
    obj.flag = false
    expect(obj.picked).to eq("B2")
  end

  describe "state defaults" do
    it "evaluates a block default once per instance (fresh object each)" do
      klass = Class.new do
        include Hibiki::Reactive

        state(:items) { [] }
      end
      a = klass.new
      b = klass.new
      a.items << 1
      expect(b.items).to be_empty
      expect(a.items).not_to equal(b.items)
    end

    it "evaluates a block default untracked, even on first read inside an effect" do
      external = Hibiki::State.new(0)
      klass = Class.new do
        include Hibiki::Reactive

        state(:snapshot) { external.value }
      end
      obj = klass.new
      runs = 0
      Hibiki::Effect.new do
        runs += 1
        obj.snapshot # first touch: default block runs in this window
      end

      external.value = 1 # must not have subscribed the effect
      expect(runs).to eq(1)
    end
  end

  it "coalesces batched writes to two states into one effect run" do
    klass = Class.new do
      include Hibiki::Reactive

      state :first, "Alan"
      state :last, "Turing"
    end
    person = klass.new
    seen = []
    Hibiki::Effect.new { seen << "#{person.first} #{person.last}" }

    Hibiki.batch do
      person.first = "Yukihiro"
      person.last = "Matsumoto"
    end
    expect(seen).to eq(["Alan Turing", "Yukihiro Matsumoto"])
  end

  it "lets subclasses inherit state and derived declarations" do
    subclass = Class.new(counter_class)
    obj = subclass.new
    obj.count = 4
    expect(obj.doubled).to eq(8)
  end

  describe "effect macro" do
    it "runs once on initialize and re-runs on writes" do
      log = []
      klass = Class.new do
        include Hibiki::Reactive

        state :count, 0
        effect { log << count }
      end

      obj = klass.new
      expect(log).to eq([0])
      obj.count = 1
      expect(log).to eq([0, 1])
    end

    it "starts effects after the user's initialize" do
      log = []
      klass = Class.new do
        include Hibiki::Reactive

        state :count, 0
        effect { log << count }

        def initialize
          self.count = 42
        end
      end

      klass.new
      expect(log).to eq([42]) # saw the constructed state, not the default
    end

    it "stops re-running after #dispose, idempotently" do
      log = []
      klass = Class.new do
        include Hibiki::Reactive

        state :count, 0
        effect { log << count }
      end

      obj = klass.new
      obj.dispose
      obj.dispose # idempotent
      obj.count = 1
      expect(log).to eq([0])
    end

    it "is adopted by a surrounding effect: owner rerun disposes it" do
      log = []
      klass = Class.new do
        include Hibiki::Reactive

        state :count, 0
        effect { log << count }
      end

      toggle = Hibiki::State.new(0)
      obj = nil
      Hibiki::Effect.new do
        toggle.value
        obj = klass.new
      end

      first = obj
      toggle.value = 1 # owner re-runs: first generation's effects disposed
      first.count = 99
      expect(log).not_to include(99)
    end

    it "runs inherited effect blocks as well as the subclass's own" do
      log = []
      parent = Class.new do
        include Hibiki::Reactive

        state :count, 0
        effect { log << [:parent, count] }
      end
      child = Class.new(parent) do
        effect { log << [:child, count] }
      end

      child.new
      expect(log).to eq([[:parent, 0], [:child, 0]])
    end
  end
end
