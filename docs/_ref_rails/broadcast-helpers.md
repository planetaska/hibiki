---
title: Broadcast helpers
nav_order: 9
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

Same replace, but delivered as a Turbo 8 morph (`method="morph"`). Morphing patches the existing DOM instead of swapping the subtree, so focus, scroll position, and unchanged elements survive the update.

**Reach for morph wherever a form can be open inside the fragment**, and treat plain `broadcast_replace` as the display-only case. A replace under an open inline form moves focus to `<body>` and drops the caret; a morph keeps both, because idiomorph pairs subtrees by id and Turbo passes `ignoreActiveValue`. On a growing list morphed at the very bottom of the document, scroll position and every element's rect measure identically before and after.

That last property has a price, and it is the one thing morph asks of your markup: **every child of the morphed container needs a stable id**. Rows, the empty-state paragraph, a trailing load-more wrapper — all of them. Idiomorph pairs by id, and an id-less trailing node is matched *positionally* against the last row and rebuilt, which is exactly the node most likely to be under the reader's cursor. Ids also have to be stable across a row's own display/edit switch, or the swap that opens the form reads as a delete plus an insert.

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

## What a channel-rendered partial can read

A partial rendered from a channel is rendered **outside a request**, and that is a bigger difference than it looks. There is no controller, so:

- `action_name` is `nil` and `controller_name` is `"application"`
- `params` and `session` are empty
- instance variables a controller would have set do not exist

**Nothing raises.** A partial that branches on `action_name == "edit"` simply takes the other branch, forever, and a partial that reads `@book` renders a blank. This is the failure mode to design against, because it looks like a rendering bug rather than a missing-context one.

The fix is to give the partial everything through locals, with defaults, and to say so at the top:

```erb
<%# locals: (books:, page: 1, editing_id: nil) -%>
```

A strict-locals header turns a forgotten local into an error at render time instead of a `nil` three lines later — worth it for any partial that two code paths render, which is every partial a render effect touches (the controller paints it first, the effect repaints it after).

`assigns:` does work, and is the escape hatch for a legacy partial you can't rewrite:

```ruby
broadcast_replace target: "book", partial: "books/book", assigns: { book: }
```

Treat it as an escape hatch rather than the normal way. It re-creates the implicit coupling that made the partial hard to render from two places to begin with.

## Where these broadcasts go

All helpers broadcast to the channel's `stream_name`, which defaults to `[channel_name, cid]` — matching the page's `<%= turbo_stream_from channel_name, cid %>`. Override `stream_name` on the channel if the page listens on different streamables. On the transmit transport none of this is involved: render effects call `transmit({ html: })` on the subscription itself (see [The JS client]({{ "/the-js-client/" | relative_url }})).
