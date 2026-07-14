# hibiki_rails

Rails glue for [hibiki](https://github.com/planetaska/hibiki):
connection-scoped signal graphs over ActionCable, pushing re-rendered HTML
to the page through Turbo Streams.

```
cable action arrives → mutate signals → effects render partials →
Turbo Streams broadcast → Turbo morphs the DOM
```

Incubating inside the hibiki repo while the core gem is pre-release; will be
extracted to its own repository once hibiki 0.1.0 ships and this API
stabilizes.

## Status

Under construction — Phase 3 of the Rails integration track.
