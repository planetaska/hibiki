# frozen_string_literal: true

module Hibiki
  # ---- class-level reactivity -------------------------------------------------
  # Svelte 5 allows $state/$derived/$effect as class fields; Reactive is the
  # Ruby analogue — declare signals with class macros, use them as plain
  # attributes:
  #
  #   class Counter
  #     include Hibiki::Reactive
  #     state :count, 0
  #     derived(:doubled) { count * 2 }
  #     effect { puts "count is now #{count}" } # starts on initialize
  #
  #     def increment = self.count += 1
  #   end
  #
  # Readers and writers are ordinary methods over per-instance signals, so
  # usage sites never touch `.value` and dependency tracking flows through
  # plain method calls. Signals are created lazily on first touch (read or
  # write): no initialize hook is needed for state/derived, and subclasses
  # inherit declarations because the generated methods inherit.
  module Reactive
    def self.included(base)
      base.extend(ClassMethods)
      base.prepend(Initializer)
    end

    module ClassMethods
      # state :count, 0
      # state(:items) { [] }
      # A positional default is shared across instances (it's one object) —
      # use the block form for mutable defaults. The block is evaluated per
      # instance, instance_exec'd, and untracked: first touch may happen
      # inside some effect's tracking window, and a default that reads other
      # signals must not subscribe that outer observer.
      def state(name, default = nil, &default_block)
        init = proc do
          State.new(default_block ? Hibiki.untrack { instance_exec(&default_block) } : default)
        end
        define_method(name) { __hibiki_signal(name, init).value }
        define_method(:"#{name}=") { |new_value| __hibiki_signal(name, init).value = new_value }
      end

      def derived(name, &)
        init = proc { Derived.new { instance_exec(&) } }
        define_method(name) { __hibiki_signal(name, init).value }
      end

      # Anonymous, so unlike state/derived it can't ride on method
      # inheritance: blocks are collected per class and gathered up the
      # ancestor chain at initialize.
      def effect(&block) = hibiki_effect_blocks << block

      def hibiki_effect_blocks = (@hibiki_effect_blocks ||= [])
    end

    # Prepended so declared effects start after the user's initialize ran
    # (they usually read state the constructor is expected to have set up).
    module Initializer
      def initialize(...)
        super
        blocks = self.class.ancestors.reverse.flat_map do |mod|
          mod.respond_to?(:hibiki_effect_blocks) ? mod.hibiki_effect_blocks : []
        end
        @__hibiki_effects = blocks.map { |block| Effect.new { instance_exec(&block) } }
      end
    end

    # Dispose every effect this instance started. Instances created inside a
    # running effect don't need this — Effect.new adopts them into the owner
    # tree and the owner's rerun/dispose takes them down. Explicitly needed
    # only for long-lived instances whose effects read signals *outside* the
    # instance (effects reading only the instance's own signals form a
    # self-contained island that garbage-collects with it).
    def dispose = @__hibiki_effects.each(&:dispose)

    private

    def __hibiki_signal(name, init)
      (@__hibiki_signals ||= {})[name] ||= instance_exec(&init)
    end
  end
end
