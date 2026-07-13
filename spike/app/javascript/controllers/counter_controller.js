import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Drives CounterChannel: subscribes with the page's graph id and forwards
// button clicks as channel actions. Rendering flows back separately, over
// the turbo_stream_from subscription.
export default class extends Controller {
  static values = { cid: String }

  connect() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "CounterChannel", cid: this.cidValue },
      {}
    )
  }

  disconnect() {
    this.subscription.unsubscribe()
    this.consumer.disconnect()
  }

  increment() {
    this.subscription.perform("increment")
  }

  burst() {
    this.subscription.perform("burst")
  }

  setStep(event) {
    this.subscription.perform("set_step", { step: event.target.value })
  }
}
