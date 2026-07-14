# frozen_string_literal: true

module Hibiki
  module Rails
    # Include into an ActionCable channel to host one connection-scoped
    # signal graph:
    #
    #   class CounterChannel < ApplicationCable::Channel
    #     include Hibiki::Rails::Channel
    #
    #     def build_graph                # runs on the graph's own thread,
    #       @count = Hibiki::State.new(0) # inside Hibiki.root
    #       Hibiki::Effect.new { ... broadcast ... }
    #     end
    #
    #     def increment = @count.value += 1  # actions are plain methods
    #   end
    #
    # Lifecycle: `subscribed` rejects without a `cid` param, then builds the
    # graph via #build_graph inside Hibiki.root on a dedicated GraphActor
    # thread; every incoming action runs on that same thread inside one
    # Hibiki.batch (N writes per action still mean one re-run per affected
    # effect); `unsubscribed` disposes the root and stops the actor.
    #
    # A channel that overrides `subscribed`/`unsubscribed` itself must call
    # `super`.
    #
    # NOTE: everything this module adds is private (except the
    # #perform_action override, which ActionCable already exposes) — any
    # other public method would be picked up by Channel#action_methods and
    # become client-invocable.
    module Channel
      def self.included(base)
        base.extend(ClassMethods)
        base.include(Broadcasts)
      end

      module ClassMethods
        private

        # #build_graph is a lifecycle hook, not a client-invocable action:
        # keep it out of action_methods even when an app defines it public
        # (a client performing "build_graph" would rebuild the graph and
        # leak the old root).
        def internal_methods = super + [:build_graph]
      end

      # ActionCable's single dispatch point for incoming actions. The whole
      # action body is posted to the graph's thread and wrapped in one
      # batch — cable threads never touch the graph. Spike-verified: batch
      # per action is all the coalescing the replace-partial style needs.
      #
      # `rescue_from` handlers still run (dispatch_action applies them
      # inside the job, now on the graph thread); what they don't handle
      # propagates to the actor's on_error — ::Rails.error by default.
      def perform_action(data)
        # A nil actor means the subscription was rejected or already torn
        # down; drop the action rather than blow up the cable thread.
        @__hibiki_actor&.post { Hibiki.batch { super(data) } }
      end

      private

      def subscribed
        super
        return reject if cid.blank?

        @__hibiki_actor = build_graph_actor
        # The block runs owned + untracked (Hibiki.root); the effects it
        # creates do their dependency-collecting first run right here, on
        # the graph thread.
        @__hibiki_actor.post { @__hibiki_root = Hibiki.root { build_graph } }
      end

      # ActionCable calls this even after a rejected subscription — hence
      # the guard. Queue#close inside GraphActor#stop lets the posted
      # dispose drain before the worker exits.
      def unsubscribed
        super
        return unless @__hibiki_actor

        @__hibiki_actor.post { @__hibiki_root.dispose }
        @__hibiki_actor.stop
      end

      # Build the signal graph: create states/deriveds/effects as instance
      # variables so actions can reach them. Runs once, on the graph's
      # thread, inside Hibiki.root.
      def build_graph
        raise NotImplementedError, "#{self.class} must implement #build_graph"
      end

      # Per-page-load graph identity, supplied by the page's subscription
      # (each tab is its own graph). Override to derive identity elsewhere.
      def cid = params[:cid]

      # Streamables the channel broadcasts to, matching the page's
      #   <%= turbo_stream_from channel_name, cid %>
      # Override when the page uses different streamables.
      def stream_name = [channel_name, cid]

      # Seam for a future pooled executor with per-graph ordering; today,
      # one worker thread per graph.
      def build_graph_actor = GraphActor.new(name: "hibiki-#{channel_name}"[0, 15])
    end
  end
end
