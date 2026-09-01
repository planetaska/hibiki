---
title: Broadcast helpers
nav_order: 10
---

# Broadcast helpers

In a hibiki_rails app the reactive graph lives on the server. *Signals*
hold values, and *effects* are blocks that re-run whenever a signal they
read changes ([Getting started]({{ "/getting-started/" | relative_url }})
introduces both). A channel builds its graph in `build_graph`, and the
workhorse pattern is a *render effect*: an effect that renders a fragment
of HTML and sends it to the browser, so the page updates every time the
data it shows changes.

The HTML can travel down one of two routes. The default is *transmit*:
the effect hands the HTML to the channel's own subscription, and the
packaged JS client swaps it into the page (see
[The JS client]({{ "/the-js-client/" | relative_url }})). The second
route is Turbo broadcasts: the effect renders a Turbo Stream, broadcasts
it to a named stream, and turbo-rails's own JavaScript applies it — no
hibiki client involved. This page documents the helpers for that second
route.

Including `Hibiki::Rails::Channel` brings them in. Each is a thin wrapper
over `Turbo::StreamsChannel`, bound to the channel's `stream_name`, so a
render effect reads as one line of intent:

```ruby
class CounterChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @count = Hibiki::State.new(0)

    Hibiki::Effect.new do
      broadcast_replace target: "count", partial: "counter/count",
                        locals: { count: @count.value }
    end
  end
end
```

`build_graph` runs once, when the browser subscribes. The effect runs
immediately and reads `@count.value`, which subscribes it to the signal;
every later write to `@count` re-runs the block, re-renders the partial,
and broadcasts the replacement.

The helpers are private on purpose. A public method on a channel becomes
an action the browser can invoke, and we don't want the browser calling
`broadcast_replace` directly.

## `broadcast_replace`

```ruby
broadcast_replace(target:, **rendering)
```

Replace the element whose DOM id is `target` with freshly rendered
content. The rendering options are whatever Turbo's renderer accepts:
`partial:` with `locals:`, a raw `html:` string (which is how
`Hibiki::Phlex.render_effect` pairs with it), and so on.

## `broadcast_morph`

```ruby
broadcast_morph(target:, **rendering)
```

The same replacement, delivered as a Turbo 8 morph (`method="morph"`).
Instead of discarding the old element and inserting the new one, a morph
walks both trees and patches only what differs — so focus, scroll
position, and every unchanged element survive the update.

**Reach for morph wherever a form can be open inside the fragment**, and
treat plain `broadcast_replace` as the display-only case. A replace under
an open inline form moves focus to `<body>` and drops the caret; a morph
keeps both, because the morph library pairs old and new subtrees by id
and leaves the element the user is typing in alone. On a growing list
morphed at the very bottom of the document, scroll position and every
element's position on screen measure identically before and after.

That precision has a price, and it is the one thing morph asks of your
markup: **every child of the morphed container needs a stable id**. Rows,
the empty-state paragraph, a trailing load-more wrapper — all of them. An
id-less trailing node cannot be paired by id, so it is matched
*positionally* against the last row and rebuilt — and it is exactly the
node most likely to be under the reader's cursor. Ids also have to stay
the same across a row's own display/edit switch, or the swap that opens
the form reads as a delete plus an insert.

## `broadcast_refresh`

```ruby
broadcast_refresh
```

Tell the page to refresh itself. This is the Turbo 8 "morph-everything"
style: the server renders no fragments at all — the page re-fetches its
own URL and morphs the fresh copy in. Pair it with debouncing when many
writes should mean one refresh, which is what the next helper does for
you.

## `broadcast_refresh_effect`

```ruby
broadcast_refresh_effect(wait: 0.25) { ...read signals... }
```

The morph-everything style as one call: creates an effect that tracks
whatever signals the block reads and answers changes with a *debounced*
`broadcast_refresh` — at most one per `wait` window. Within one action,
`Hibiki.batch` already coalesces writes into one effect run; the debounce
covers the cross-action case, so a burst of quick actions produces one
page refresh, not one per action. The initial dependency-collecting run
broadcasts immediately, like every effect's first run.

```ruby
def build_graph
  @list = TodoList.new
  broadcast_refresh_effect { @list.items }  # any change to items → one refresh per burst
end
```

## Rendering outside a request

A partial rendered from a channel is rendered **outside a request**, and
that is a bigger difference than it looks. There is no controller, so:

- `action_name` is `nil` and `controller_name` is `"application"`
- `params` and `session` are empty
- instance variables a controller would have set do not exist

**Nothing raises.** A partial that branches on `action_name == "edit"`
simply takes the other branch, forever, and a partial that reads `@book`
renders a blank. This is the failure mode to design against, because it
looks like a rendering bug rather than a missing-context one.

The fix is to give the partial everything through locals, with defaults,
and to say so at the top:

```erb
<%# locals: (books:, page: 1, editing_id: nil) -%>
```

A strict-locals header turns a forgotten local into an error at render
time instead of a `nil` three lines later. That is worth it for any
partial that two code paths render — which is every partial a render
effect touches, because the controller renders it first and the effect
re-renders it after.

`assigns:` does work, and is the escape hatch for a legacy partial you
can't rewrite:

```ruby
broadcast_replace target: "book", partial: "books/book", assigns: { book: }
```

Treat it as an escape hatch rather than the normal way. It re-creates the
implicit coupling that made the partial hard to render from two places to
begin with.

## Which stream they broadcast to

All the helpers broadcast to the channel's `stream_name`, which defaults
to `[channel_name, cid]`, where `cid` is the per-page-load id the
subscription was opened with — matching a page that subscribed with
`<%= turbo_stream_from channel_name, cid %>`. Override `stream_name` on
the channel if the page listens on different streamables. The transmit
transport involves none of this: there, render effects call
`transmit({ html: })` on the subscription itself (see
[The JS client]({{ "/the-js-client/" | relative_url }})).
