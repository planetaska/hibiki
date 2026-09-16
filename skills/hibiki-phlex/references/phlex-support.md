# Phlex support (hibiki_phlex 0.1.0)

Deps: `hibiki` and `phlex` only (pinned `>= 2.4, < 2.5`), Ruby >= 3.4; add `phlex-rails` to render from views.

## API

| Name | What it does |
|---|---|
| `Hibiki::Phlex.render_effect(component, scheduler: nil, &block)` | Wraps the render in a `Hibiki::Effect`; the first run renders at once and collects deps; each rerun re-renders the same instance and yields the HTML string to the block; returns the `Effect` |
| `Hibiki::Phlex::Rerenderable#rerender(...)` | Clears Phlex's private `@_state` and calls the component again; required by `render_effect` |

Without the module it raises `ArgumentError` (`<Class> has no #rerender — include
Hibiki::Phlex::Rerenderable`). `scheduler:` is a callable receiving the effect
that calls `effect.run` when ready. An owner (`Hibiki.root`, another effect)
disposes the returned effect; a bare caller calls `dispose`.

## Component recipe

Include `Hibiki::Reactive` (signals as methods) and `Rerenderable` (one
instance renders again); add `Hibiki::Rails::Helpers` only for `on` and friends.

```ruby
class TodoList < Phlex::HTML
  include Hibiki::Reactive
  include Hibiki::Phlex::Rerenderable

  state(:items) { [] }                       # block: fresh array per instance
  derived(:remaining) { items.count { |i| !i[:done] } }

  def view_template
    div(id: "todos") do                      # root id = swap key, page-unique
      h2 { "Todos: #{remaining} remaining" }
      ul { items.each { |item| li { item[:title] } } }
    end
  end

  def add(title) = self.items = items + [{ title:, done: false }]   # new value, not <<
end
```

Equal writes (`==`) are no-ops and a derived recomputes on read. Inside
`module Hibiki` write `::Phlex::HTML`; the bare constant resolves to `Hibiki::Phlex`.

## In a hibiki_rails channel

```ruby
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph                      # once per subscription, on the graph thread
    @list = TodoList.new               # the one long-lived instance
    Hibiki::Phlex.render_effect(@list) { |html| transmit({ html: }) }
  end

  def add(data) = @list.add(data["title"])   # public method = client action
end
```

Island wrapper, a Phlex component any page can `render`:
```ruby
class TodoListIsland < Phlex::HTML
  include Hibiki::Rails::Helpers

  def view_template
    div(**hibiki_island(TodosChannel, cid: SecureRandom.uuid)) do
      render TodoList.new              # throwaway placeholder
      form(**on(:add, event: :submit)) { input(name: "title"); button { "add" } }
    end
  end
end
```

`hibiki_island` and `on` return `{ data: {...} }` hashes: splat them (`island`
is ERB-only and raises). Inside the component: `button(**on(:toggle, with: { index: }))`.

## Routes for the HTML

| Route | Block | Needs | Notes |
|---|---|---|---|
| Transmit (default) | `transmit({ html: })` | nothing extra | client swaps by root id; first transmit always lands |
| Broadcast | `broadcast_replace target: "todos", html:` | `turbo_stream_from` inside the island | Turbo stream actions (morph); first-update ordering trap |

## Deferring

```ruby
scheduler = Hibiki::Rails::Debounce.new(actor: graph_actor, wait: 0.2)
Hibiki::Phlex.render_effect(@list, scheduler:) { |html| transmit({ html: }) }
```

One render per `wait` window across actions (writes within one action are
already batched); the first render is never deferred. One effect re-renders
one whole component, so split into smaller components for finer updates.

## The pin

Phlex marks a rendered instance solely via `@_state` and raises
`Phlex::DoubleRenderError` on a second call; `rerender` clears it. A gemspec
allowlist plus a contract spec guard that, so do not loosen the pin in an app.

## Not the scaffold's `--phlex`

| | `hibiki_phlex` | scaffold `--phlex` |
|---|---|---|
| State owner | component | channel |
| Instance | one per subscription, `Rerenderable` | new per render, stateless |
| Re-rendered by | `render_effect` | channel `broadcast_replace renderable:` |
| Namespace | `Components::` in `app/components` | `Views::` in `app/views` |

See also: https://planetaska.github.io/hibiki/crud-notes/
Full docs: https://planetaska.github.io/hibiki/phlex-support/
