// The packaged client for hibiki_rails: one generic Stimulus controller
// that drives any island stamped by the Hibiki::Rails::Helpers Ruby
// helpers. Stimulus is the lifecycle host only (connect/disconnect across
// Turbo navigation, morphs, and dynamic insertion); the wire protocol is
// hibiki-owned data attributes, so server-side components never write
// Stimulus vocabulary and a non-Stimulus client can speak the same
// attributes (toy-phlex's vanilla driver is the proof).
//
// The attribute contract (private to this gem — emitted by the Ruby
// helpers, interpreted here, versioned together):
//
//   island root   data-controller="hibiki"
//                 data-hibiki-channel-value="CounterChannel"
//                 data-hibiki-cid-value="<per-page-load id>"
//   controls      data-hibiki-on="<event>-><action>"   e.g. "click->increment"
//                 data-hibiki-with='{"index":3}'       optional JSON payload
//
// Transport is the channel's own subscription both ways: the server's
// render effects `transmit({ html: })` fragments that are swapped in by
// their root DOM id, and control events are `perform`ed as channel
// actions. `received` is registered at subscribe time — before the server
// runs build_graph — so the effects' first transmits always land; the
// server-rendered initial HTML is only a paint-avoidance placeholder.
//
// Register under the identifier "hibiki" (the helpers hardcode it):
//
//   import HibikiController from "hibiki"
//   application.register("hibiki", HibikiController)
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// One consumer shared by every island — ActionCable multiplexes
// subscriptions over a single websocket. Never disconnected: islands come
// and go with the DOM, the socket stays.
let consumer

export default class HibikiController extends Controller {
  static values = { channel: String, cid: String }

  connect() {
    consumer ??= createConsumer()
    this.subscription = consumer.subscriptions.create(
      { channel: this.channelValue, cid: this.cidValue },
      { received: (data) => this.received(data) }
    )
    // Root-scoped delegation (bound to the island, not document): controls
    // inside server-replaced fragments keep working with no rebinding.
    this.listeners = ["click", "change", "submit"].map((type) => {
      const handler = (event) => this.forward(event)
      this.element.addEventListener(type, handler)
      return [type, handler]
    })
  }

  disconnect() {
    for (const [type, handler] of this.listeners) {
      this.element.removeEventListener(type, handler)
    }
    this.subscription?.unsubscribe()
  }

  // Server → DOM: swap each transmitted fragment in by its root id.
  received({ html }) {
    const template = document.createElement("template")
    template.innerHTML = html
    for (const fragment of [...template.content.children]) {
      document.getElementById(fragment.id)?.replaceWith(fragment)
    }
  }

  // DOM → server: forward a control's event as a channel action. Nested
  // islands: events bubble to every ancestor island's listener, so each
  // controller only acts when the control belongs to ITS island.
  forward(event) {
    const control = event.target.closest("[data-hibiki-on]")
    if (!control) return
    if (control.closest('[data-controller~="hibiki"]') !== this.element) return

    const token = control.dataset.hibikiOn
      .split(/\s+/)
      .find((t) => t.startsWith(`${event.type}->`))
    if (!token) return

    const action = token.slice(event.type.length + 2)
    const payload = control.dataset.hibikiWith
      ? JSON.parse(control.dataset.hibikiWith)
      : {}
    if (event.type === "submit") {
      event.preventDefault()
      Object.assign(payload, Object.fromEntries(new FormData(control)))
    } else if (event.type === "change" && control.name) {
      payload[control.name] = control.value
    }
    this.subscription.perform(action, payload)
    if (event.type === "submit") control.reset()
  }
}

export { HibikiController }

// For islands on the OTHER transport — Turbo-stream broadcasts instead of
// transmit — the graph's first broadcast is lost unless the page's
// <turbo-cable-stream-source> has already confirmed ITS subscription.
// Await this before subscribing the graph channel: it resolves once Turbo
// stamps the `connected` attribute on the stream source, so the effects'
// dependency-collecting first run broadcasts into a live stream.
export function streamConnected(element) {
  if (element.hasAttribute("connected")) return Promise.resolve()

  return new Promise((resolve) => {
    const observer = new MutationObserver(() => {
      if (element.hasAttribute("connected")) {
        observer.disconnect()
        resolve()
      }
    })
    observer.observe(element, { attributeFilter: ["connected"] })
  })
}
