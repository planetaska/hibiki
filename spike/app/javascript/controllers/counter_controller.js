import { ChannelController } from "hibiki-rails"

// Drives CounterChannel on the packaged ChannelController base: the
// identifier "counter" infers the channel name, increment/burst are
// auto-forwarded from the view's data-action tokens, and only setStep is
// declared because it builds a payload from the event. Rendering flows
// back over the turbo_stream_from subscription — the base awaits that
// stream source before subscribing — so this page stays the live proof
// of the Turbo-broadcast transport (and now of the subclass shape); the
// todos and /phlex-counter pages prove the generic controller + transmit.
export default class extends ChannelController {
  setStep(event) {
    this.perform("set_step", { step: event.target.value })
  }
}
