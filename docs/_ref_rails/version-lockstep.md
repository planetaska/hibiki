---
title: Version lockstep
nav_order: 13
---

# Version lockstep

`hibiki_rails` ships in two halves: the Ruby gem, and the
[`hibiki-rails` npm package](https://www.npmjs.com/package/hibiki-rails),
which is the same JavaScript module the gem's engine vendors. The two are
released together under matching version numbers — every gem release
publishes an npm release, even when the client did not change — so an app
that installs from npm follows one rule: **pin both halves to the same
version**. An importmap app gets this for free, because it serves the copy
vendored inside the gem.

| `hibiki_rails` gem | `hibiki-rails` npm | notes |
| ------------------ | ------------------ | ----- |
| 0.11.0             | 0.11.0             | the client takes its Action Cable consumer from `@hotwired/turbo-rails` (`cable.getConsumer()`) instead of importing `@rails/actioncable`: islands and `turbo_stream_from` share one websocket, bundler apps shed a second copy of the library, importmap apps need no `@rails/actioncable` pin. npm peer: `@hotwired/turbo-rails >= 8.0` replaces `@rails/actioncable` |
| 0.10.0             | 0.10.0             | no client change (on the gem side, [`hibiki:rails:upload_field`]({{ "/file-uploads/" | relative_url }}) — attachments on both edit surfaces, `--accept`, `--many` galleries) |
| 0.9.1              | 0.9.1              | no client change (on the gem side, [`hibiki:rails:nested`]({{ "/nested-forms/" | relative_url }}) creates a missing child model from its field list) |
| 0.9.0              | 0.9.0              | `perform` on the island controller becomes public API, with a `performOn` export — [drive an island from your own JavaScript]({{ "/driving-an-island/" | relative_url }}). Also fixes `perform` claiming success (a truthy seq) for an action dropped during an offline gap |
| 0.8.0              | 0.8.0              | `fallback:` — a control's native href/action as its degraded path (stand-aside off-`ready`, dead-socket fallthrough, CSRF freshening) — and `history.replaceState` for the channel's `transmit_url` |
| 0.7.0              | 0.7.0              | a `[]`-suffixed field name collects **all** its FormData entries as an array — a multi-select's full selection reaches the channel |
| 0.6.0              | 0.6.0              | no client change (the AR-equality release on the gem side) |
| 0.5.0              | 0.5.0              | no client change: `@rails/actioncable` becomes a peer dependency (it was double-bundled), and the gem's Rails floor moves to 8.0 |
| 0.4.0              | 0.4.0              | loading and connection state: `data-hibiki-busy`, `aria-busy`, `data-hibiki-state`, the reserved `hbk` payload key, and actions queued until the subscription confirms |
| 0.3.0              | 0.3.0              | `input` + debounce, the `visible` sentinel, event lists, `confirm:`/`reset:`, correct checkbox and multi-select payloads, subscribe params |
| 0.2.0              | 0.2.0              | reactive values (`data-hibiki-value`) |
| 0.1.0              | 0.1.0              | initial release |

## Upgrading

The [changelog](https://github.com/planetaska/hibiki-rails/blob/main/CHANGELOG.md)
carries the per-release detail. One historical note: **0.3.0 fixed a
security issue affecting Rails 7.1 and 7.2 apps only** — channel lifecycle
methods were client-invocable there, because the ActionCable hook the gem
used to hide them exists on 8.x alone. It matters for 0.4.0 and earlier;
from 0.5.0 the gem requires Rails 8.0, so those Rails versions cannot run
it at all.
