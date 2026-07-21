---
title: Error handling layers
nav_order: 9
---

# Error handling layers

1. `rescue_from` on the channel — handles action errors, on the graph
   thread.
2. `Hibiki.error_handler = ->(error, effect) { ... }` — app-level routing
   for effect errors raised during a flush (the gem does not set this).
3. The graph worker's per-job rescue — everything unhandled lands in
   `Rails.error.report(..., source: "hibiki_rails")`. Override per channel
   via `build_graph_actor` and `GraphActor.new(on_error:)`.