# Driving an island from your own JavaScript

For gestures no markup attribute can declare (a drag library's drop callback,
a canvas widget, a `window` keyboard shortcut), fire the action from code.

```js
import { performOn } from "hibiki-rails"
performOn(element, "your_action", { your_payload })   // any element inside the island
```

`performOn` finds the containing island (no Stimulus context needed) and
calls the island controller's public `perform(action, payload)`, so the
payload reaches the server in the same shape and the island shows the same
busy state. Inside a Stimulus controller you can reach the instance yourself:

```js
const islandEl = this.element.closest('[data-controller~="hibiki"]')
const island = this.application.getControllerForElementAndIdentifier(islandEl, "hibiki")
island?.perform("your_action", { your_payload })   // null until the island connected
```

| Return | Meaning | You do |
| --- | --- | --- |
| truthy (the trip's seq) | accepted: sent live, or queued during the first connect window | leave the DOM as the user arranged it; the incoming update is a visual no-op |
| `undefined` | dropped: island offline, socket dead at send, or (`performOn` only, with a console warning) no island contains the element | revert the gesture, or let the next update self-heal |

Nothing queues across an offline gap: a reconnect builds a fresh graph, so a
stale "move row to 3" could reorder a list that has changed underneath.

Drag-to-reorder with SortableJS on a nested fieldset (the library owns the
gesture, your controller owns the handoff):

```js
// app/javascript/controllers/credits_sortable_controller.js
import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { performOn } from "hibiki-rails"

export default class extends Controller {
  static values = { dom: String }
  connect() {
    this.sortable = Sortable.create(this.element, {
      handle: "[data-drag-handle]", animation: 150, onEnd: (e) => this.dropped(e)
    })
  }
  disconnect() { this.sortable.destroy() }
  dropped({ item, oldIndex, newIndex }) {
    if (newIndex === oldIndex) return
    const accepted = performOn(this.element, "nested_move",
      { dom: this.domValue, path: item.dataset.path, to: newIndex })
    if (accepted) return
    const siblings = [...this.element.children].filter((row) => row !== item)
    this.element.insertBefore(item, siblings[oldIndex] ?? null)   // no update is coming
  }
}
```

A morph replaces the container, Stimulus reconnects the controller, and the
Sortable instance is rebuilt. `nested_move` comes from
`Hibiki::Rails::NestedActions` (the `hibiki-rails-forms` skill).

What the server receives: the public method named by the action, with one
string-keyed hash: your payload plus `action` (ActionCable's dispatch key) and
`hbk` (the busy seq, stripped by `perform_action` before your method runs).
Treat it as untrusted, like request params:

```ruby
def set_color(data)
  hex = data["hex"].to_s
  return unless hex.match?(/\A#\h{6}\z/)
  @color.value = hex          # write the signal; effects re-render on their own
end
```

If the value equals what the signal holds, nothing re-runs and no bytes go
out, and busy still clears on the ack.

Full docs: https://planetaska.github.io/hibiki/driving-an-island/
