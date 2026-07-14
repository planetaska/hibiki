import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { streamConnected } from "controllers/stream_connected"

// Drives TodosChannel; the toggle buttons live inside the broadcast-replaced
// component, which is fine because this controller sits on an ancestor node.
// Subscribes only after the page's Turbo stream connects, so the render
// effect's first broadcast lands (see stream_connected.js).
export default class extends Controller {
  static values = { cid: String }
  static targets = ["title"]

  async connect() {
    this.consumer = createConsumer()
    await streamConnected(this.element.querySelector("turbo-cable-stream-source"))
    this.subscription = this.consumer.subscriptions.create(
      { channel: "TodosChannel", cid: this.cidValue },
      {}
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer.disconnect()
  }

  add(event) {
    event.preventDefault()
    const title = this.titleTarget.value.trim()
    if (title === "") return
    this.subscription.perform("add", { title })
    this.titleTarget.value = ""
  }

  toggle(event) {
    this.subscription.perform("toggle", { index: event.params.index })
  }
}
