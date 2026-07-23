---
title: Broadcast helpers
nav_order: 10
---

# Broadcast helpers

Including `Hibiki::Rails::Channel` also brings in a small set of rendering helpers for the Turbo-broadcast transport: thin wrappers over `Turbo::StreamsChannel`, all bound to the channel's `stream_name`, so a render effect reads as one line of intent:

```ruby
def build_graph
  @count = Hibiki::State.new(0)

  Hibiki::Effect.new do
    broadcast_replace target: "count", partial: "counter/count",
                      locals: { count: @count.value }
  end
end
```

They are private on purpose — a public method on a channel becomes a client-invocable action, and nobody wants the browser calling `broadcast_replace` directly.

## `broadcast_replace(target:, **rendering)`

Replace the element with DOM id `target`. The rendering options are whatever Turbo's renderer accepts: `partial:`/`locals:`, a raw `html:` string (which is how `Hibiki::Phlex.render_effect` pairs with it), and so on.

## `broadcast_morph(target:, **rendering)`

Same replace, but delivered as a Turbo 8 morph (`method="morph"`). Morphing patches the existing DOM instead of swapping the subtree, so focus, scroll position, and unchanged elements survive the update. Prefer it for fragments the user interacts with; plain `broadcast_replace` is fine for display-only fragments.

## `broadcast_refresh`

Tell the page to refresh itself — the Turbo 8 "morph-everything" style, where the server doesn't render fragments at all and the page just re-fetches and morphs. Pair it with debouncing when many writes should mean one refresh.

## `broadcast_refresh_effect(wait: 0.25) { ...read signals... }`

The morph-everything style as one call: creates an effect that tracks whatever signals the block reads and answers changes with a *debounced* `broadcast_refresh`. `Hibiki.batch` already coalesces the writes within one action; the debounce covers the cross-action case — a burst of quick actions produces one page refresh per `wait` window, not one per action. The initial dependency-collecting run broadcasts immediately, like every effect's first run.

```ruby
def build_graph
  @list = TodoList.new
  broadcast_refresh_effect { @list.items }  # any change to items → one refresh per burst
end
```

## Where these broadcasts go

All helpers broadcast to the channel's `stream_name`, which defaults to `[channel_name, cid]` — matching the page's `<%= turbo_stream_from channel_name, cid %>`. Override `stream_name` on the channel if the page listens on different streamables. On the transmit transport none of this is involved: render effects call `transmit({ html: })` on the subscription itself (see [The JS client]({{ "/the-js-client/" | relative_url }})).
