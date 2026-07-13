import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Drives TodosChannel; the toggle buttons live inside the broadcast-replaced
// component, which is fine because this controller sits on an ancestor node.
export default class extends Controller {
  static values = { cid: String }
  static targets = ["title"]

  connect() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "TodosChannel", cid: this.cidValue },
      {}
    )
  }

  disconnect() {
    this.subscription.unsubscribe()
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
