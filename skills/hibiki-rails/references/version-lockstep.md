# Version lockstep

`hibiki_rails` ships in two halves: the Ruby gem and the npm package
`hibiki-rails`, the same JavaScript module the engine vendors. Every gem
release publishes an npm release under the same number, even when the client
did not change. Rule: pin both halves to the same version. Importmap apps get
this for free because they serve the copy inside the gem.

| gem = npm | Client change |
| --- | --- |
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
