// The app's ENTIRE first-party JavaScript: a generic driver with no
// counter-specific code. For each [data-hibiki-channel] root it opens one
// channel subscription, swaps in whatever HTML fragments the server
// transmits (matched by the fragment's DOM id), and forwards
// data-hibiki-action clicks / data-hibiki-change inputs as channel actions.
//
// One subscription does both directions, so there is no Turbo stream to
// wait for (the spike's stream_connected.js) — the client registers its
// `received` callback at subscribe time, before the server ever builds the
// graph, so the effects' first transmits always land.
import { createConsumer } from "@rails/actioncable"

const consumer = createConsumer()

for (const root of document.querySelectorAll("[data-hibiki-channel]")) {
  const subscription = consumer.subscriptions.create(
    { channel: root.dataset.hibikiChannel, cid: root.dataset.hibikiCid },
    {
      received({ html }) {
        const template = document.createElement("template")
        template.innerHTML = html
        const fragment = template.content.firstElementChild
        document.getElementById(fragment.id)?.replaceWith(fragment)
      }
    }
  )

  root.addEventListener("click", (event) => {
    const action = event.target.closest("[data-hibiki-action]")?.dataset.hibikiAction
    if (action) subscription.perform(action)
  })

  root.addEventListener("change", (event) => {
    const action = event.target.dataset.hibikiChange
    if (action) subscription.perform(action, { [event.target.name]: event.target.value })
  })
}
