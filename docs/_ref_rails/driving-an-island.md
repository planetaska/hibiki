---
title: Driving an island from JS
nav_order: 7
---

# Driving an island from your own JavaScript

Some gestures can't be declared in markup — a drag library's drop callback, a canvas widget, a keyboard shortcut. For those, **`perform(action, payload)` on the island's controller instance is public API** (0.9.0): it fires the action through the island's own subscription, exactly like a declared control, busy state and all. Reach the instance with Stimulus's standard lookup:

```js
// inside one of your own Stimulus controllers
const islandEl = this.element.closest('[data-controller~="hibiki"]')
const island = this.application.getControllerForElementAndIdentifier(islandEl, "hibiki")
island?.perform("your_action", { your_payload })
```

(The optional chaining matters: the lookup returns `null` until the island's controller has connected.)

**Or** skip the incantation above with the `performOn` export, which finds the island containing any element — no Stimulus context required:

```js
import { performOn } from "hibiki-rails"

performOn(element, "your_action", { your_payload })
```

**The return value is the whole contract.** Truthy — the trip's sequence number — means the action was *accepted*: sent live, or queued during the island's initial connect window. A repaint is coming, so leave the DOM as the user arranged it; the morph will land as a visual no-op. `undefined` means it was *dropped*: the island is offline, the socket turned out to be dead at send, or (`performOn` only, with a console warning) no island contains the element. The caller owns recovery — revert the gesture, or stand back and let the next repaint self-heal. Nothing queues across an offline gap, on purpose: a reconnect builds a fresh server-side graph, and replaying intent formed against the old one is worse than dropping it.

## Worked example: drag-to-reorder with SortableJS

Third-party UI libraries slot in the same way whatever they do: the library owns the gesture, your controller owns the handoff, `perform`/`performOn` is the handoff.

Here is drag-to-reorder on a [nested fieldset]({{ "/nested-forms/" | relative_url }}) with [SortableJS](https://sortablejs.github.io/Sortable/):

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
    // Failed (or offline): no repaint is coming — put the row back.
    const siblings = [...this.element.children].filter((row) => row !== item)
    this.element.insertBefore(item, siblings[oldIndex] ?? null)
  }
}
```

The markup side is all plain app attributes — wrap the generated fieldset's rows and give each row a handle and its path:

```erb
<div data-controller="credits-sortable" data-credits-sortable-dom-value="<%= dom %>">
  <% visible_credits.each_with_index do |credit, index| %>
    <%= render "songs/credit_fields", credit: credit, dom: dom,
               path: "credits/#{credit.nested_key}", index: index,
               count: visible_credits.size %>
  <% end %>
</div>
```

One drop, one `nested_move`, and every session converges on the server's order — the dragging tab's repaint is a visual no-op because the DOM already looks that way. The scaffold's ↑/↓ buttons keep working beside the drag, and the wiring survives repaints: Stimulus disconnects and reconnects the controller when a morph replaces the container.

### Where the payload lands

On the channel there is nothing to write for this example — `nested_move` is one of the generic actions [`hibiki:rails:nested`]({{ "/nested-forms/" | relative_url }}) already included:

```ruby
# app/channels/songs_channel.rb (as generated)
class SongsChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel
  # nested_add / nested_remove / nested_move / nested_set_field
  include Hibiki::Rails::NestedActions
  # ...
end
```

A performed action reaches the channel like any ActionCable action: the public method named by the action runs with one hash — the payload you passed, **string keys**, plus two reserved entries stamped on the way out (`action`, ActionCable's dispatch key, and `hbk`, the sequence number behind [busy tracking]({{ "/loading-state/" | relative_url }})). For the drop above, `nested_move` receives:

```ruby
{ "action" => "nested_move", "hbk" => 7,
  "dom" => "song_42", "path" => "credits/c3", "to" => 2 }
```

and consumes it like this (the gem's own implementation, shown for what it does with those keys):

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

A custom action for your own gesture is the same shape: a public method on the channel (which makes it client-invocable — keep everything else private), one `data` hash, keys read as strings and treated as untrusted, writes going to the graph's signals so the repaint follows. If nothing it writes actually changes, no bytes go out — that is the equality gate working, not a fault — and the busy indicator still clears on the post-batch ack.
