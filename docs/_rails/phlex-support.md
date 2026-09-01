---
title: Phlex support
nav_order: 7
---

# Phlex support

The sister gem `hibiki_phlex` makes Phlex components reactive. A Phlex component is a plain Ruby object, so `Hibiki::Reactive` gives it per-instance signals read as ordinary method calls — no `.value` anywhere in `view_template` — and a **render effect** re-renders it whenever one of those signals changes.

```
signal write → render effect re-runs → component re-renders
(same instance) → fresh HTML handed to your block
```

The gem is transport-agnostic on purpose: it depends only on `hibiki` and `phlex`. The block receiving the HTML decides where it goes — broadcast it over Turbo Streams, transmit it down a channel subscription, write it to a file, diff it in a test.

The gem requires Phlex >= 2.4, < 2.5 (see the version-pin rationale below) and Ruby >= 3.4:

```ruby
# Gemfile
gem "hibiki_phlex"
```

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

- The effect's **first run is the dependency-collecting initial render**: signals read inside `view_template` subscribe it through plain method calls, and that first HTML is yielded too.
- Re-renders happen **on the same instance** — signal identity lives in the instance, so a fresh instance per render would reset every signal. That's what `Rerenderable` exists for.
- `render_effect(component, scheduler:)` passes the scheduler through to `Hibiki::Effect`, so reruns can be deferred or debounced (e.g. `Hibiki::Rails::Debounce`).
- `render_effect` returns the `Hibiki::Effect`. When it is created inside `Hibiki.root` (or another effect), the owner tree disposes it automatically; a bare caller calls `#dispose`.

## With hibiki_rails

The combination is the LiveView-ish loop — one signal graph per cable connection, one render effect per component:

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

Granularity is inherent and worth knowing: the ERB style in `hibiki_rails` runs one effect **per partial** (fine-grained); a Phlex render effect runs one **per component** (component-grained). Both are correct; pick per page. The placeholder-then-first-update ordering (subscribe only after the Turbo stream confirms) belongs to the transport, not to Phlex; see [Placeholders and the first update]({{ "/rails-usage/" | relative_url }}#placeholders-and-the-first-update). On the transmit transport there is no such ordering problem (see [The JS client]({{ "/the-js-client/" | relative_url }})).

## Why the strict Phlex pin

Phlex components are one-shot: an instance renders once, and a second `call` raises `Phlex::DoubleRenderError`. Phlex 2 tracks "spent" purely through the private `@_state` ivar — everything else about a render is per-call — so `Rerenderable#rerender` clears it and calls again. That is the entire adapter, but it leans on a private implementation detail, so:

- the gemspec allows only verified Phlex minors (`>= 2.4, < 2.5`), and
- a contract spec pins the upstream behavior itself, so bumping the bound fails loudly in CI if the internals moved.

## Not the same as the scaffold's `--phlex`

**Two different Phlex idioms live in this project.** On this page a *component* owns reactive state, and a render effect re-renders it. The CRUD scaffold's `--phlex` flag is the other one: there the *channel* owns the state, so its components are ordinary stateless views and `hibiki_phlex` is not involved at all. If that is what you are after, see [Phlex instead of ERB]({{ "/crud-notes/#phlex-instead-of-erb" | relative_url }}).
