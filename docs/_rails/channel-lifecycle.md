---
title: Channel lifecycle
nav_order: 9
---

# Channel lifecycle

This page explains what `include Hibiki::Rails::Channel` actually does under the hood, at each point in a subscription's life. You don't need any of this to use the gem — read it when you want to know where your code runs, or before overriding `subscribed` / `unsubscribed` (if you do, call `super`).

The central idea: ActionCable dispatches incoming commands on a thread pool with **no per-channel ordering**, while hibiki's threading model is confinement — a graph must only ever be touched from one thread. So the concern gives every subscription a dedicated worker thread (a `GraphActor`), and cable threads only ever enqueue closures onto it. The graph is built, mutated, and disposed on exactly that one thread.

**On subscribe** — the subscription is rejected without a `cid` param. Otherwise the concern starts the worker thread and posts `build_graph` to it, wrapped in `Hibiki.root`: the states, deriveds, and effects you create there are owned by that root, and the effects do their dependency-collecting first run right there, on the graph thread.

**On every action** — the whole action body is posted to the graph thread and wrapped in one `Hibiki.batch`, so N signal writes in one action still mean one re-run per affected effect. `rescue_from` handlers still apply — they just run on the graph thread now; whatever they don't handle is reported to `Rails.error` with source `"hibiki_rails"` (see [Error handling layers]({{ "/error-handling-layers/" | relative_url }})).

**Each job is its own unit of work.** Graph build, action and flush each run inside `Rails.application.executor`, which is what makes a long-lived worker thread safe: autoloads are permitted concurrently, each job gets its own Active Record query cache, and — the one with teeth — **`ActiveSupport::CurrentAttributes` are reset between jobs**. So `Current.user` set during one action is *gone* by the next one, and anything set on the cable thread never reaches the graph thread at all. If your channel needs request-ish context, derive it from the connection identity (which `ActionCable::Connection` already establishes) at the point of use, rather than assigning it once and expecting it to persist.

**On unsubscribe** — the concern disposes the root (running any `on_cleanup` hooks) and stops the worker. Already-queued actions drain first; anything posted after that is silently dropped rather than crashing a cable thread — a user navigating away can always race an in-flight click.

**On code reload (development)** — an engine hook disposes every live graph before Rails reloads code, because stale effects would keep running old class versions forever. Cable clients auto-reconnect and rebuild the graph. Graph state therefore resets on reload, like any remount — expected in development, and worth remembering when a counter "mysteriously" jumps back to zero after you edit a file.
