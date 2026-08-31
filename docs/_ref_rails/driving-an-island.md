---
title: Driving an island from JS
nav_order: 7
---

# Driving an island from your own JavaScript

An island normally needs no JavaScript from you. The `on` helper declares
which DOM events become channel actions, and the packaged controller does
the rest: it listens for those events, sends each one up the island's
channel subscription, and swaps the re-rendered HTML back in when the
server answers ([The JS client]({{ "/the-js-client/" | relative_url }})
covers that cycle). But some gestures never surface as a DOM event you
could declare: a drag library reports a drop through its own callback, a
canvas widget tracks the pointer itself, a keyboard shortcut lives on
`window`. For those, the client lets your own code fire an action
directly.

## Firing an action from code

The simplest entry point is the `performOn` export. Give it any element
inside the island, an action name, and a payload:

```js
// inside any JavaScript file where you need to call a channel action
import { performOn } from "hibiki-rails"

performOn(element, "your_action", { your_payload })
```

`performOn` finds the island containing the element — no Stimulus context
required — and fires the action through that island's subscription,
exactly as if a declared control had fired it: the payload reaches the
server in the same shape, and the island shows the same
[busy indicator]({{ "/loading-state/" | relative_url }}) while the round
trip is in flight.

If your code already runs inside a Stimulus controller, you can instead
reach the island's controller instance and call **`perform`** on it —
public API since 0.9.0, and the method `performOn` calls for you. Use
Stimulus's standard lookup:

```js
// inside one of your own Stimulus controllers
// the performOn() introduced above does all of these for you,
// so you can skip this incantation
const islandEl = this.element.closest('[data-controller~="hibiki"]')
const island = this.application.getControllerForElementAndIdentifier(islandEl, "hibiki")
island?.perform("your_action", { your_payload })
```

(The optional chaining matters: the lookup returns `null` until the
island's controller has connected.)

## Accepted or dropped: the return value

In this stack every user gesture is a round trip: the action travels up the
socket, the server updates its signals, and the changed HTML travels back
down to be swapped in. `perform` and `performOn` return synchronously,
before any of that happens, and the return value answers one question —
did the action get on its way?

- **Truthy** — the trip's sequence number — means the action was
  *accepted*: sent live, or queued during the island's initial connect
  window. An update is coming, so leave the DOM as the user arranged it;
  when the server's HTML lands, the swap is a visual no-op because the
  page already looks that way.
- **`undefined`** means the action was *dropped*: the island is offline,
  the socket turned out to be dead at send, or (`performOn` only, with a
  console warning) no island contains the element. No update is coming,
  and you own the recovery — revert the gesture, or stand back and let
  the next update self-heal.

We deliberately made sure nothing queues across an offline gap. When the
connection comes back, the server builds a brand-new signal graph, so an
action held from before the gap would land on state that no longer
matches what the user was looking at — a "move this row to position 3"
could reorder a list that has since changed under it. Firing stale
actions at a fresh graph does the wrong thing more often than firing
nothing, so the client drops them instead. The first connect window is
the one exception: the page and the graph are being built together, so
actions queued there are safe to flush.
[Loading and connection state]({{ "/loading-state/" | relative_url }})
covers both windows.

## Worked example: drag-to-reorder with SortableJS

Third-party UI libraries slot in the same way whatever they do: the
library owns the gesture, your Stimulus controller owns the handoff, and
`performOn` is the handoff.

Here is drag-to-reorder on a
[nested fieldset]({{ "/nested-forms/" | relative_url }}) with
[SortableJS](https://sortablejs.github.io/Sortable/). SortableJS moves
the row in the DOM and reports the drop through its `onEnd` callback —
exactly the kind of gesture no markup attribute can declare:

```js
// app/javascript/controllers/credits_sortable_controller.js
import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { performOn } from "hibiki-rails"

export default class extends Controller {
  static values = { dom: String }

  connect() {
    this.sortable = Sortable.create(this.element, {
      handle: "[data-drag-handle]",
      animation: 150,
      onEnd: (event) => this.dropped(event)
    })
  }

  disconnect() {
    this.sortable.destroy()
  }

  dropped({ item, oldIndex, newIndex }) {
    if (newIndex === oldIndex) return
    // The container holds only visible rows, so Sortable's newIndex IS
    // nested_move's "index among visible siblings".
    const accepted = performOn(this.element, "nested_move", {
      dom: this.domValue, path: item.dataset.path, to: newIndex
    })
    if (accepted) return
    // Failed (or offline): no update is coming — put the row back.
    const siblings = [...this.element.children].filter((row) => row !== item)
    this.element.insertBefore(item, siblings[oldIndex] ?? null)
  }
}
```

Both branches of the contract are visible in `dropped`. Accepted: return
and leave the row where the user dropped it — the server will reorder its
side to match, and the update changes nothing visibly. Failed: no
update will undo the drag, so the controller puts the row back itself.

The markup side is all plain app attributes — wrap the generated
fieldset's rows and give each row a handle and its path:

```erb
<div data-controller="credits-sortable" data-credits-sortable-dom-value="<%= dom %>">
  <% visible_credits.each_with_index do |credit, index| %>
    <%= render "songs/credit_fields", credit: credit, dom: dom,
               path: "credits/#{credit.nested_key}", index: index,
               count: visible_credits.size %>
  <% end %>
</div>
```

One drop sends one `nested_move`, the server reorders, and every session
looking at the form converges on the server's order. The scaffold's ↑/↓
buttons keep working beside the drag, and the wiring survives re-renders:
when a morph replaces the container, Stimulus disconnects and reconnects
the controller, which rebuilds the Sortable instance.

## What the server receives

For this example the channel needs nothing new — `nested_move` is one of
the generic actions [`hibiki:rails:nested`]({{ "/nested-forms/" |
relative_url }}) already included:

```ruby
# app/channels/songs_channel.rb (as generated)
class SongsChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel
  # nested_add / nested_remove / nested_move / nested_set_field
  include Hibiki::Rails::NestedActions
  # ...
end
```

A performed action reaches the channel like any ActionCable action: the
public method named by the action runs with one hash. That hash is the
payload you passed, with **string keys**, plus two reserved entries
stamped on the way out — `action`, ActionCable's dispatch key, and `hbk`,
the sequence number behind
[busy tracking]({{ "/loading-state/" | relative_url }}). For the drop
above, `nested_move` receives:

```ruby
{ "action" => "nested_move", "hbk" => 7,
  "dom" => "song_42", "path" => "credits/c3", "to" => 2 }
```

and consumes it like this (the gem's own implementation, shown for what
it does with those keys):

```ruby
# Hibiki::Rails::NestedActions
def nested_move(data)
  # "dom" names the open form, "path" walks to the child — every hop
  # gated against the form's declarations, so a stale or forged path
  # resolves to nothing and the action drops.
  owner, name, child = __hibiki_nested_target(data)
  return unless child && !data["to"].nil?

  # `to` is the index among visible siblings; the form clamps it.
  owner.nested_move(name, child, to: data["to"].to_i)
end
```

A custom action for your own gesture takes the same shape: a public
method on the channel, one `data` hash, keys read as strings and treated
as untrusted — a performed payload is client-supplied, exactly like
request params. (Being public is what makes the method invocable from the
client, so keep everything else on the channel private.) The method's job
is to write to the graph's signals; the re-render follows on its own,
because the rendering effects re-run when the values they read change.

Suppose the canvas widget from the introduction is a color picker, and
picking a color fires:

```js
performOn(canvas, "set_color", { hex: picked })
```

Then the channel side is one public method and one guarded write:

```ruby
class ThemeChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @color = Hibiki::State.new("#000000")
    # ... effects that read @color.value and transmit HTML ...
  end

  # runs with { "action" => "set_color", "hbk" => n, "hex" => "#a3e2b8" }
  def set_color(data)
    hex = data["hex"].to_s
    return unless hex.match?(/\A#\h{6}\z/)  # client-supplied — validate before writing

    @color.value = hex
  end
end
```

Nothing else is needed. The method never renders and never transmits:
writing the signal is its whole job, and the effects built in
`build_graph` notice the change and send the new HTML down on their own.

One corollary worth knowing before it surprises you: if `set_color`
receives the color the signal already holds, the write changes nothing,
so no effect re-runs and no bytes go out. That is Hibiki's equality gate working — and the busy indicator still clears, because clearing rides on the server's acknowledgment of the action, not on a render arriving.
