# frozen_string_literal: true

module Hibiki
  module Rails
    # An Effect scheduler (Vue's ReactiveEffect scheduler; the core seam is
    # pinned by the "scheduler:" group in hibiki's spec/effect_spec.rb) that
    # coalesces invalidation bursts into at most one run per `wait` window —
    # trailing edge, so the run sees then-current state.
    #
    # Hibiki.batch already coalesces the writes WITHIN one action; this is
    # for the cross-action case, where many actions in quick succession
    # should mean one re-run — Turbo 8's broadcast_refresh style wants one
    # page refresh per burst, not one per action.
    #
    # Threading: the scheduler fires on the graph's actor thread (effects
    # only re-run there), and the disarm+run is posted back to the same
    # actor, so @armed needs no lock. The timer thread only sleeps. If the
    # actor stops before the timer fires, post returns false and the run is
    # dropped — teardown wins, same as Effect#run no-opping once disposed.
    class Debounce
      def initialize(actor:, wait:)
        @actor = actor
        @wait = wait
        @armed = false
      end

      def call(effect)
        return if @armed

        @armed = true
        Thread.new do
          sleep @wait
          @actor.post do
            @armed = false
            effect.run
          end
        end
      end
    end
  end
end
