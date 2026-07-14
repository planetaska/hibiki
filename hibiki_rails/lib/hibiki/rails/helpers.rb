# frozen_string_literal: true

require "json"

module Hibiki
  module Rails
    # Opt-in helpers that stamp the packaged client's attribute protocol
    # (interpreted by the vendored hibiki.js Stimulus controller). Strictly
    # opt-in, mirroring Hibiki::DSL: include it where you want the bare
    # names — ApplicationHelper for ERB views, individual Phlex components —
    # the gem never includes it for you.
    #
    #   div(**hibiki_island(CounterChannel, cid:)) do
    #     button(**on(:increment)) { "+" }
    #     button(**on(:toggle, with: { index: 3 })) { "toggle" }
    #     input(name: "step", **on(:set_step, event: :change))
    #     form(**on(:add, event: :submit)) { ... }
    #   end
    #
    # Both helpers return a `{ data: { ... } }` hash: splat it into Phlex
    # element methods or Rails tag helpers (`tag.div(**hibiki_island(...))`).
    # When the element needs other attributes on the same `data:` key, merge
    # the hashes yourself (Phlex's `mix` does this).
    #
    # The emitted attribute names are a private contract between these
    # helpers and the gem's JS — they version together; don't hand-write
    # them in app code.
    module Helpers
      # The island root: one channel subscription per island, identified by
      # a per-page-load cid (each tab is its own graph). `channel` is the
      # channel class or its name as a string.
      def hibiki_island(channel, cid:)
        channel_name = channel.is_a?(Class) ? channel.name : channel.to_s
        { data: { controller: "hibiki", hibiki_channel_value: channel_name,
                  hibiki_cid_value: cid } }
      end

      # Forward a DOM event on this element as a channel action. `event:`
      # picks the DOM event (:click, :change, :submit); `with:` is a hash
      # sent as the action's payload. The client adds event-derived data on
      # top: a changed control contributes `{ name => value }`, a submitted
      # form contributes its FormData (and is reset after the perform).
      def on(action, event: :click, with: nil)
        data = { hibiki_on: "#{event}->#{action}" }
        data[:hibiki_with] = JSON.generate(with) unless with.nil?
        { data: }
      end
    end
  end
end
