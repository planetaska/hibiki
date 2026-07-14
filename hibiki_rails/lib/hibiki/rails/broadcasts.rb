# frozen_string_literal: true

module Hibiki
  module Rails
    # Rendering helpers for effects: thin wrappers over Turbo::StreamsChannel
    # bound to the channel's #stream_name, so a render effect reads as
    #
    #   Hibiki::Effect.new do
    #     broadcast_replace target: "count", partial: "counter/count",
    #                       locals: { count: @count.value }
    #   end
    #
    # All private — a public helper would become a client-invocable action
    # (see the NOTE on Hibiki::Rails::Channel).
    module Broadcasts
      private

      # Replace the element with DOM id `target` (accepts partial:/locals:,
      # html:, or anything Turbo's renderer takes).
      def broadcast_replace(target:, **rendering)
        Turbo::StreamsChannel.broadcast_replace_to(*stream_name, target:, **rendering)
      end

      # Replace via Turbo 8 morphing (<turbo-stream action="replace"
      # method="morph">): keeps focus/scroll where a plain replace resets.
      def broadcast_morph(target:, **rendering)
        Turbo::StreamsChannel.broadcast_replace_to(
          *stream_name, target:, attributes: { method: :morph }, **rendering
        )
      end

      # Tell the page to refresh itself (Turbo 8 morph-everything style).
      # Pair with Debounce when many writes should mean one refresh.
      def broadcast_refresh
        Turbo::StreamsChannel.broadcast_refresh_to(*stream_name)
      end

      # The Morph-everything style as one call: an effect that tracks
      # whatever `deps` reads and answers changes with a debounced page
      # refresh — one refresh per burst of actions, not one per action.
      # The initial (dependency-collecting) run broadcasts immediately, as
      # every Effect.new does. Requires the channel context (graph_actor).
      def broadcast_refresh_effect(wait: 0.25, &deps)
        scheduler = Debounce.new(actor: graph_actor, wait:)
        Hibiki::Effect.new(scheduler:) do
          deps.call
          broadcast_refresh
        end
      end
    end
  end
end
