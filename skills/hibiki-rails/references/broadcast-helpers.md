# Broadcast helpers

The Turbo-broadcast route: an effect renders a Turbo Stream, broadcasts it to
a named stream, and turbo-rails' JavaScript applies it. `include
Hibiki::Rails::Channel` brings the helpers in (via `Hibiki::Rails::Broadcasts`);
all are private so the browser cannot invoke them as actions, and all target
the channel's `stream_name`, default `[channel_name, cid]`, which matches
`<%= turbo_stream_from channel_name, cid %>` (what `island` writes).

| Helper | Does |
| --- | --- |
| `broadcast_replace(target:, **rendering)` | replaces the element with DOM id `target`; `rendering` is `partial:` + `locals:`, `html:`, or anything Turbo's renderer takes |
| `broadcast_morph(target:, **rendering)` | the same as a Turbo 8 morph (`method="morph"`): patches only what differs, so focus, caret, scroll survive |
| `broadcast_refresh` | tells the page to re-fetch its own URL and morph it in |
| `broadcast_refresh_effect(wait: 0.25) { ...reads... }` | an effect on a `Hibiki::Rails::Debounce` scheduler: one `broadcast_refresh` per `wait` window across actions; the first run broadcasts immediately |

```ruby
def build_graph
  @count = Hibiki::State.new(0)
  Hibiki::Effect.new do
    broadcast_replace target: "count", partial: "counter/count", locals: { count: @count.value }
  end
end
```

Morph or replace:

- Reach for `broadcast_morph` wherever a form can be open inside the
  fragment; a replace moves focus to `<body>` and drops the caret.
- Morph requires a stable id on every child of the morphed container (rows,
  the empty-state paragraph, a trailing load-more wrapper). An id-less node is
  paired positionally and rebuilt. Keep a row's id the same across its
  display/edit switch, or the swap reads as delete plus insert.
- Treat plain `broadcast_replace` as the display-only case.

Rendering outside a request:

- `action_name` is nil, `controller_name` is `"application"`, `params` and
  `session` are empty, controller ivars do not exist. Nothing raises: a
  partial branching on `action_name == "edit"` takes the other branch forever.
- Pass everything through `locals:` with defaults, under a strict-locals
  header, so a forgotten local errors at render time:

```erb
<%# locals: (books:, page: 1, editing_id: nil) -%>
```

- `assigns:` works as an escape hatch for a legacy partial
  (`broadcast_replace target: "book", partial: "books/book", assigns: { book: }`)
  but re-creates the coupling that made it hard to render from two places.

Override `stream_name` when the page listens on other streamables. The
transmit route involves none of this: effects call `transmit({ html: })` and
the island needs no stream line.

Full docs: https://planetaska.github.io/hibiki/broadcast-helpers/
