# Version lockstep

`hibiki_rails` ships in two halves: the Ruby gem and the npm package
`hibiki-rails`, the same JavaScript module the engine vendors. Every gem
release publishes an npm release under the same number, even when the client
did not change. Rule: pin both halves to the same version. Importmap apps get
this for free because they serve the copy inside the gem.

| gem = npm | Client change |
| --- | --- |
| 0.20.1 | numbers each subscription's actions from 1 with no gaps, so the channel can run them in the order sent (Action Cable could swap two sent back to back, such as typed input and the click after it); fixes an action running before the value typed just ahead of it. Needs both halves |
| 0.20.0 | runs `js` command lists (`on(js.hide(...))`) through the new module `hibiki-rails/commands`, which an existing app must import; opens and closes a `<dialog>` from `modal(open:)`; `on` hears a dialog's `cancel` and `close`; a morph keeps a dialog's `open` (see commands) |
| 0.19.0 | `transmit_url(history: :push)` makes URL moves history entries, and `on(:action, event: :popstate)` answers Back and Forward (see reactive-values) |
| 0.18.0 | with `HibikiController.reportTrips = true`, times each round trip and reports it with the next action under the reserved `hbt` key (gem side: the `*.hibiki_rails` instrumentation events and `registry.tally`; see instrumentation) |
| 0.17.2 | none (`ReactiveForm#commit` unloads `reactive_association` targets before writing and after a refusal; fixes `RecordNotUnique` on the save after a refused one, and wrong saves after another session's) |
| 0.17.1 | applies Turbo broadcast renders in the order the channel sent them (`broadcast_replace` and `broadcast_morph` number each one); fixes a page ending on the older of two renders of one target. Needs both halves |
| 0.17.0 | a field with unsent debounced input keeps its text and caret through a render, and an undebounced action flushes pending input first; keys in `on` (`keydown.<key>`, `@window`); the `focus` helper; focus returns to a control when a render removes the focused element |
| 0.16.0 | assigns DOM properties from `props` (`indeterminate`, `scrollTop`, `scrollLeft`) on connect and after every render; rescans on `turbo:render`, so props and `visible` survive a page refresh |
| 0.15.0 | `hibiki-rails/motion` module (`data-motion`, `data-motion-leaving`/`-entering`); `islandFor` and `hibiki:before-render` seams; scaffold emits motion, `--skip-motion` |
| 0.14.0 | none (scaffold's load-more split into a `visible` sentinel + fallback link) |
| 0.13.0 | none (scaffold query object moves to `app/queries`) |
| 0.12.0 | none (the `island` block helper) |
| 0.11.0 | consumer from `@hotwired/turbo-rails` (`cable.getConsumer()`); no `@rails/actioncable` pin; npm peer `@hotwired/turbo-rails >= 8.0` |
| 0.10.0 | none (`hibiki:rails:upload_field`) |
| 0.9.x | `perform` public, `performOn` export; dropped actions return `undefined` |
| 0.8.0 | `fallback:` and `history.replaceState` for `transmit_url` |
| 0.7.0 | `[]`-suffixed fields collect all entries as an array |
| 0.5.0 | Rails floor 8.0; `@rails/actioncable` a peer |
| 0.4.0 | `data-hibiki-busy`, `aria-busy`, `data-hibiki-state`, reserved `hbk`, connect-window queue |
| 0.3.0 | `input` + debounce, `visible`, event lists, `confirm:`/`reset:`, subscribe params; fixed client-invocable lifecycle methods on Rails 7.1/7.2 |
| 0.2.0 | reactive values (`data-hibiki-value`) |

Full docs: https://planetaska.github.io/hibiki/version-lockstep/
