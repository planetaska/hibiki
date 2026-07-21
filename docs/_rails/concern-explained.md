---
title: Concern explained
nav_order: 7
---

## What the concern does

- `subscribed` — rejects without a `cid` param, then runs `build_graph`
  inside `Hibiki.root` on a dedicated worker thread (a `GraphActor`).
  ActionCable dispatches on a thread pool with no per-channel ordering;
  hibiki's threading model is confinement — so cable threads only enqueue,
  and the graph lives on exactly one thread.
- every action — the whole body is posted to that thread wrapped in one
  `Hibiki.batch`. `rescue_from` still applies (it runs on the graph
  thread); what it doesn't handle goes to `Rails.error` (source
  `"hibiki_rails"`).
- `unsubscribed` — disposes the root (running `on_cleanup` hooks) and
  stops the worker, draining what was already queued.
- dev reloading — an Engine hook disposes every live graph before code
  reloads (stale effects would run old class versions forever); cable
  clients auto-reconnect and rebuild. Graph state resets on reload, like
  any remount.