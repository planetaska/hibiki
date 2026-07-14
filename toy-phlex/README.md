# toy-phlex — the full-Phlex counter

The spike app's counter, rebuilt with a 100% Phlex view layer
([app/views/counter/show.rb](app/views/counter/show.rb) renders the whole
document, doctype to `</html>`) to answer one question: **how much JS does a
hibiki page need when the server owns all rendering?**

Answer: one first-party file. [app/javascript/application.js](app/javascript/application.js)
is a generic ~40-line driver — it subscribes to the channel named by
`data-hibiki-channel`, replaces fragments the server transmits (matched by
DOM id), and forwards `data-hibiki-action` clicks / `data-hibiki-change`
inputs as channel actions. Nothing in it knows about counters.

Compared to the spike, this app drops:

- **Turbo JS** — the render effects `transmit` HTML down the channel's own
  subscription instead of broadcasting over a Turbo stream
  (`Hibiki::Phlex.render_effect`'s block owns the transport).
- **Stimulus + per-page controllers** — buttons carry `data-hibiki-action`
  attributes rendered by Phlex; the generic driver forwards them.
- **stream_connected.js** — with a single subscription there is no
  Turbo-stream-vs-channel ordering race to paper over.

Run it: `bin/rails server -p 3001` (or the `toy-phlex` entry in
`.claude/launch.json`). Development-only — there are no production/test
environment files.
