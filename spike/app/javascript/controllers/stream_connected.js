// The initial-state pattern for hibiki_rails (no _controller suffix, so
// Stimulus does not register this file — it is a plain helper module).
//
// The graph's effects do their first, dependency-collecting run inside the
// channel's `subscribed`, and that first broadcast is lost unless the
// page's <turbo-cable-stream-source> has already confirmed ITS
// subscription. So: wait for Turbo to stamp the `connected` attribute on
// the stream source, then subscribe the graph channel — the first effect
// run's broadcast always lands, and the server-rendered initial HTML is
// only a paint-avoidance placeholder, not a correctness requirement.
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
