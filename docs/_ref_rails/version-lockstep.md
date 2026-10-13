---
title: Version lockstep
nav_order: 16
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
| 0.20.1             | 0.20.1             | a channel runs its actions in the order the browser sent them. Action Cable could run two actions sent back to back in either order, so a click made straight after typing could reach the channel before the typed value. The client now numbers each subscription's actions from 1 with none missing, and the channel waits up to 100 ms for one that is late. Update both halves together: a client older than 0.20.1 works with the new gem, but its first action after a reconnect waits those 100 ms |
| 0.20.0             | 0.20.0             | commands and dialogs. `on` takes a list of commands built with `js`, which the browser runs with no round trip: show and hide, classes, attributes, focus, a DOM event, a dialog, and a channel action among them. The new module `hibiki-rails/commands` runs them; the install generator imports it, and an existing app adds `import "hibiki-rails/commands"` itself. `modal(open:)` lets a channel open and close a `<dialog>`, `on` hears a dialog's `cancel` and `close`, and a morph keeps a dialog's `open` attribute. See [Commands and dialogs]({{ "/commands/" | relative_url }}) |
| 0.19.0             | 0.19.0             | history entries. `transmit_url(history: :push)` makes each move of the URL an entry in the browser's history, and `on(:action, event: :popstate)` answers Back and Forward. The default is still `replaceState`. See [Reactive values]({{ "/reactive-values/" | relative_url }}#history-entries) |
| 0.18.0             | 0.18.0             | instrumentation. A channel publishes `ActiveSupport::Notifications` events for subscribing, actions and renders, with nothing to configure. With `HibikiController.reportTrips = true` the client also times each round trip and reports it with the next action, under the new reserved payload key `hbt`; a client older than 0.18.0 reports none. See [Instrumentation]({{ "/instrumentation/" | relative_url }}) |
| 0.17.2             | 0.17.2             | no client change (on the gem side, two fixes to forms that declare `reactive_association`. A save the model refused could leave the form unable to save again, and a form that had already saved once could save its selection wrongly after another session changed the same record. `commit` now compares the selection with the table each time; see [Multi-select associations]({{ "/multiselect/" | relative_url }})) |
| 0.17.1             | 0.17.1             | a fix in both halves. Action Cable can deliver two broadcast renders out of order, and a page that drew both into one target ended on the older one. `broadcast_replace` and `broadcast_morph` now number their renders, and the client applies them in the order the channel sent them. One half alone behaves as 0.17.0 did |
| 0.17.0             | 0.17.0             | focus and keys, all in the client. A field with unsent debounced input keeps its text and caret through a render, and an undebounced action first sends the island's pending input. `on` takes keys (`keydown.esc`, `keydown.ctrl+s`, `keydown.n@window`). The new `focus` view helper puts the cursor in a field that a render opens, and focus returns to a control when a render removes the focused element — see [The JS client]({{ "/the-js-client/#keys" | relative_url }}) |
| 0.16.0             | 0.16.0             | the client assigns DOM properties that no HTML attribute can express, on connect and after every render: a checkbox's `indeterminate` and a container's scroll position, written by the new `props` view helper — see [The JS client]({{ "/the-js-client/#dom-properties" | relative_url }}). The island also rescans after a Turbo page refresh, so a `visible` control keeps firing after `broadcast_refresh` |
| 0.15.0             | 0.15.0             | the `hibiki-rails/motion` module: a marked element (`data-motion`) finishes its transition before a render removes it, with the public `data-motion-leaving` / `data-motion-entering` attributes — see [Motion explained]({{ "/motion-explained/" | relative_url }}). `hibiki.js` gains the seams it needs (`islandFor`, a `hibiki:before-render` event before a transmit swap). On the gem side the scaffold emits motion by default under the styled variants, with `--skip-motion` to leave it out |
| 0.14.0             | 0.14.0             | no client change (on the gem side, the scaffold's infinite-scroll Load-more control is split: a visible-only sentinel wrapper and a fallback link inside it with a real `?page=N` href, so the control works without JavaScript; see [CRUD notes]({{ "/crud-notes/" | relative_url }}#the-address-bar-and-life-without-javascript)) |
| 0.13.0             | 0.13.0             | no client change (on the gem side, the scaffold's query object moves to `app/queries`; add-ons find it in either place) |
| 0.12.0             | 0.12.0             | no client change (on the gem side, the `island` block helper: the ERB form of the island root, which folds the cid, `hibiki_island`, and the channel's `turbo_stream_from` into one call; see [The JS client]({{ "/the-js-client/" | relative_url }})) |
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
