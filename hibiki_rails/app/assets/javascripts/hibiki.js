// The packaged client for hibiki_rails. Two shapes, one plumbing:
//
// 1. The generic controller (HibikiController, register as "hibiki"):
//    drives any island stamped by the Hibiki::Rails::Helpers Ruby
//    helpers. Stimulus is the lifecycle host only (connect/disconnect
//    across Turbo navigation, morphs, and dynamic insertion); the wire
//    protocol is hibiki-owned data attributes, so server-side components
//    never write Stimulus vocabulary and a non-Stimulus client can speak
//    the same attributes (toy-phlex's vanilla driver is the proof).
// 2. The subclassable base (ChannelController): for apps that prefer the
//    familiar Stimulus structure (data-controller="counter",
//    data-action="counter#increment"). The base owns the consumer, the
//    subscription lifecycle, and transport handling; plain actions are
//    auto-forwarded to the channel, so a subclass only declares a method
//    when it needs something custom:
//
//      import { ChannelController } from "hibiki-rails"
//
//      // identifier "counter" infers CounterChannel (override with
//      // `static channel = "..."` when the names don't line up)
//      export default class extends ChannelController {
//        setStep(event) {
//          this.perform("set_step", { step: event.target.value })
//        }
//      }
//
// Both shapes speak both transports. Transmit: the server's render
// effects `transmit({ html: })` fragments that are swapped in by their
// root DOM id; `received` is registered at subscribe time — before the
// server runs build_graph — so the effects' first transmits always land
// (the server-rendered initial HTML is only a paint-avoidance
// placeholder). Turbo broadcasts: when the controller's element contains
// its own <turbo-cable-stream-source> (turbo_stream_from), the graph's
// first broadcast is lost unless that stream has already confirmed ITS
// subscription — so connect awaits it (streamConnected) before
// subscribing, and rendering flows back over the Turbo stream while
// `received` stays idle.
//
// The attribute contract of the generic controller (private to this gem —
// emitted by the Ruby helpers, interpreted here, versioned together):
//
//   island root   data-controller="hibiki"
//                 data-hibiki-channel-value="CounterChannel"
//                 data-hibiki-cid-value="<per-page-load id>"
//   controls      data-hibiki-on="<event>-><action>"   e.g. "click->increment"
//                 data-hibiki-with='{"index":3}'       optional JSON payload
//
// Register the generic controller under the identifier "hibiki" (the
// helpers hardcode it):
//
//   import HibikiController from "hibiki-rails"
//   application.register("hibiki", HibikiController)
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// One consumer shared by every controller — ActionCable multiplexes
// subscriptions over a single websocket. Never disconnected: islands come
// and go with the DOM, the socket stays.
let consumer

// camelCase Stimulus method name → snake_case Ruby channel action.
const underscore = (name) => name.replace(/([A-Z])/g, "_$1").toLowerCase()

// The subclassable base: one channel subscription per controller element,
// identified by a per-page-load cid (data-<identifier>-cid-value).
export class ChannelController extends Controller {
  static values = { cid: String }

  async connect() {
    this.aborted = false
    consumer ??= createConsumer()
    this.defineForwarders()
    // Turbo-broadcast transport: wait for the element's own stream source
    // to confirm before subscribing, so the graph's dependency-collecting
    // first run broadcasts into a live stream. No source (transmit
    // transport) → this path is fully synchronous, exactly as before.
    const source = this.streamSource()
    if (source) await streamConnected(source)
    if (this.aborted) return // disconnected during the await
    this.subscription = consumer.subscriptions.create(
      { channel: this.channelName(), cid: this.cidValue },
      { received: (data) => this.received(data) }
    )
  }

  disconnect() {
    this.aborted = true
    this.subscription?.unsubscribe()
    this.subscription = undefined
  }

  // DOM → server: what declared action methods call.
  perform(action, payload = {}) {
    this.subscription.perform(action, payload)
  }

  // Server → DOM (transmit transport): swap each transmitted fragment in
  // by its root id. Broadcast-transport channels never transmit, and a
  // non-html transmit is not ours to interpret. Subclasses may override.
  received({ html }) {
    if (!html) return
    const template = document.createElement("template")
    template.innerHTML = html
    for (const fragment of [...template.content.children]) {
      document.getElementById(fragment.id)?.replaceWith(fragment)
    }
  }

  // `static channel = "..."` wins; otherwise infer Rails-style from the
  // identifier: "counter" → CounterChannel, "my-thing" → MyThingChannel.
  channelName() {
    if (this.constructor.channel) return this.constructor.channel
    const pascal = this.identifier
      .split(/[-_]/)
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
      .join("")
    return `${pascal}Channel`
  }

  // Auto-forwarding: every data-action token addressed to this identifier
  // whose method the subclass did NOT declare gets a generated forwarder
  // that performs the underscored action with no payload — so plain
  // forwards need zero code. Declared methods always win. Methods are
  // defined at connect: action NAMES first appearing in later-inserted
  // markup aren't discovered (names already seen keep working anywhere,
  // Stimulus binds the elements itself).
  defineForwarders() {
    for (const control of this.element.querySelectorAll("[data-action]")) {
      for (const token of control.dataset.action.trim().split(/\s+/)) {
        const method = this.forwardableMethod(token)
        if (method && typeof this[method] !== "function") {
          this[method] = () => this.perform(underscore(method))
        }
      }
    }
  }

  // Token forms: "identifier#method", "event->identifier#method", plus
  // trailing :options — returns the method name, or null when the token
  // addresses another controller.
  forwardableMethod(token) {
    const descriptor = token.includes("->") ? token.split("->")[1] : token
    const [identifier, method] = descriptor.split("#")
    if (identifier !== this.identifier || !method) return null
    return method.split(":")[0]
  }

  // The element's own <turbo-cable-stream-source>, if any. Scoped like
  // forward() below: a nested controller's source belongs to IT.
  streamSource() {
    return [...this.element.querySelectorAll("turbo-cable-stream-source")].find(
      (s) => s.closest(`[data-controller~="${this.identifier}"]`) === this.element
    )
  }
}

// The generic controller: adds the data-hibiki-* wire protocol on top of
// the base's plumbing.
export default class HibikiController extends ChannelController {
  static values = { channel: String } // cid inherited from the base

  // The island stamps its channel; no inference.
  channelName() {
    return this.channelValue
  }

  async connect() {
    // Root-scoped delegation (bound to the island, not document): controls
    // inside server-replaced fragments keep working with no rebinding.
    // Set up synchronously so disconnect can always tear them down.
    this.listeners = ["click", "change", "submit"].map((type) => {
      const handler = (event) => this.forward(event)
      this.element.addEventListener(type, handler)
      return [type, handler]
    })
    await super.connect()
  }

  disconnect() {
    for (const [type, handler] of this.listeners) {
      this.element.removeEventListener(type, handler)
    }
    super.disconnect()
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
    this.perform(action, payload)
    if (event.type === "submit") control.reset()
  }
}

export { HibikiController }

// The Turbo-broadcast race helper the base uses internally, still
// exported for custom (non-Stimulus) clients: resolves once Turbo stamps
// the `connected` attribute on the given <turbo-cable-stream-source>.
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
