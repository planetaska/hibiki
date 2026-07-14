# hibiki_phlex

Phlex glue for [hibiki](https://github.com/planetaska/hibiki): reactive
components. A Phlex component is a plain Ruby object, so
`Hibiki::Reactive` gives it per-instance signals read as ordinary method
calls — no `.value` anywhere in `view_template` — and a **render effect**
re-renders it whenever one of those signals changes.

```
signal write → render effect re-runs → component re-renders
(same instance) → fresh HTML handed to your block
```

Transport-agnostic on purpose: the gem depends only on hibiki and phlex.
The block receiving the HTML decides where it goes — broadcast it over
Turbo Streams (see [hibiki_rails](../hibiki_rails)), write it to a file,
diff it in a test.

Incubating inside the hibiki repo while the core gem is pre-release; will
be extracted to its own repository once hibiki 0.1.0 ships and this API
stabilizes. Phlex >= 2.4, < 2.5 (see the version-pin rationale below),
Ruby >= 3.4.

## Usage

```ruby
class TodoList < Phlex::HTML
  include Hibiki::Reactive
  include Hibiki::Phlex::Rerenderable

  state(:items) { [] }
  derived(:remaining) { items.count { |item| !item[:done] } }

  def view_template
    div(id: "todos") do
      h2 { "Todos — #{remaining} remaining" }
      ul { items.each { |item| li { item[:title] } } }
    end
  end

  # Signals compare with ==; build new values instead of mutating in place.
  def add(title) = self.items = items + [{ title:, done: false }]
end
```

```ruby
list = TodoList.new

effect = Hibiki::Phlex.render_effect(list) do |html|
  # your transport — e.g. inside a Hibiki::Rails::Channel:
  # broadcast_replace target: "todos", html:
end

list.add("write docs")   # → the block runs again with fresh HTML
effect.dispose           # or let an enclosing Hibiki.root own teardown
```

- The effect's **first run is the dependency-collecting initial render**:
  signals read inside `view_template` subscribe it through plain method
  calls, and that first HTML is yielded too.
- Re-renders happen **on the same instance** — signal identity lives in
  the instance, so a fresh instance per render would reset every signal.
  That's what `Rerenderable` exists for.
- `render_effect(component, scheduler:)` passes the scheduler through to
  `Hibiki::Effect`, so reruns can be deferred or debounced (e.g.
  `Hibiki::Rails::Debounce`).
- Returns the `Hibiki::Effect`. Created inside `Hibiki.root` (or another
  effect), the owner tree disposes it automatically; a bare caller calls
  `#dispose`.

## With hibiki_rails

The combination is the LiveView-ish loop — one signal graph per cable
connection, one render effect per component:

```ruby
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @list = TodoList.new
    Hibiki::Phlex.render_effect(@list) do |html|
      broadcast_replace target: "todos", html:
    end
  end

  def add(data) = @list.add(data["title"])
end
```

Granularity is inherent and worth knowing: the ERB style in hibiki_rails
is one effect **per partial** (fine-grained), a Phlex render effect is one
effect **per component** (component-grained). Both are correct; pick per
page. The initial-state pattern (server-rendered placeholder + subscribe
after the Turbo stream confirms) is transport-side — see the hibiki_rails
README.

## Why the strict Phlex pin

Phlex components are one-shot: an instance renders once, and a second
`call` raises `Phlex::DoubleRenderError`. Phlex 2 tracks "spent" purely
through the private `@_state` ivar — everything else about a render is
per-call — so `Rerenderable#rerender` clears it and calls again. That is
the entire adapter, but it leans on a private implementation detail, so:

- the gemspec allows only verified Phlex minors (`>= 2.4, < 2.5`), and
- `spec/phlex_contract_spec.rb` pins the upstream contract itself, so
  bumping the bound fails loudly in CI if the internals moved.

## Development

```
bundle exec rake   # specs + rubocop (same as CI)
```

Plain RSpec — no Rails; the live end-to-end proof app is `spike/` in the
parent repo (the `/phlex` page).
