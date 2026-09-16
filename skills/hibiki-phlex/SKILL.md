---
name: hibiki-phlex
description: >-
  Reactive Phlex components with the hibiki_phlex gem (0.1.0): a Phlex::HTML
  class including Hibiki::Reactive (per-instance state/derived signals) and
  Hibiki::Phlex::Rerenderable, wrapped by Hibiki::Phlex.render_effect(component,
  scheduler:) { |html| ... }, which re-renders the same instance on each signal
  change and yields fresh HTML. Covers use in a hibiki_rails channel
  with transmit({ html: }) or broadcast_replace(target:, html:), the island
  wrapper via hibiki_island and on, deferring with Hibiki::Rails::Debounce, the
  strict Phlex pin (>= 2.4, < 2.5) and why, Phlex::DoubleRenderError, the
  hibiki:rails:phlex generator, and how component-owns-state differs from the
  scaffold's --phlex (channel-owns-state, stateless Views:: components). Load
  for any Phlex component that should re-render by itself, "component does not
  re-render", "DoubleRenderError", "has no #rerender", or "phlex vs --phlex".
  Load hibiki for the signal core, hibiki-rails for channels and the JS client,
  hibiki-rails-scaffold for --phlex.
license: MIT
metadata:
  author: planetaska
  hibiki: "0.3.0"
  hibiki_rails: "0.15.0"
  hibiki_phlex: "0.1.0"
---

# hibiki-phlex

`hibiki_phlex` 0.1.0 makes a Phlex component reactive. The versions table for
the whole gem family lives in the `hibiki` skill.

## What it does

Two pieces do the work, and the gem adds nothing else:

- **Signals in the component.** `Hibiki::Reactive`, from the core gem, lets a
  class declare `state` and `derived` signals that the template reads as plain
  method calls. Each read is tracked, which is what tells the render effect
  what the template depends on.
- **A render effect around the component.** `Hibiki::Phlex.render_effect`
  wraps the component's render in a `Hibiki::Effect`, so a change to any
  signal the template read renders the same instance again and passes the
  new HTML to your block.

The gem depends on `hibiki` and `phlex` only, so the block owns the
transport: transmit it down a channel, broadcast it, print it, or diff it in
a test.

## Install

```ruby
# Gemfile
gem "hibiki_phlex"
```

Ruby 3.4 or later, and Phlex pinned to `>= 2.4, < 2.5` (see
[Why the Phlex pin is strict](#why-the-phlex-pin-is-strict)). Add `phlex-rails`
yourself to render components from Rails views, since `hibiki_phlex` does not
pull it in. A Rails app also wants `hibiki_rails` for the channel and the
packaged client; the `hibiki-rails` skill has its install steps.

## A reactive component

```ruby
class TodoList < Phlex::HTML
  include Hibiki::Reactive
  include Hibiki::Phlex::Rerenderable

  state(:items) { [] }
  derived(:remaining) { items.count { |item| !item[:done] } }

  def view_template
    div(id: "todos") do
      h2 { "Todos: #{remaining} remaining" }
      ul { items.each { |item| li { item[:title] } } }
    end
  end

  def add(title) = self.items = items + [{ title:, done: false }]
end
```

Line by line:

- `state(:items) { [] }` declares a writable signal; every instance gets its
  own, and the block gives each a fresh array. Use a block for any mutable
  default, because a positional default would be one array shared by every
  instance.
- `derived(:remaining) { ... }` is lazy: it recomputes when read after
  `items` changed, never on the write itself.
- Read signals as plain method calls in the template. There is no `.value`,
  yet each read subscribes the render effect.
- Include `Rerenderable` so one instance can render more than once, which
  Phlex normally refuses. The render effect requires it.
- Replace the array in `add` instead of appending, because a signal notices a
  write only when the new value differs by `==`, and an array mutated in place
  is equal to itself.

## The render effect

```ruby
list = TodoList.new

effect = Hibiki::Phlex.render_effect(list) do |html|
  puts html
end
# prints the list with 0 remaining

list.add("write docs")
# prints again, with 1 remaining

effect.dispose
```

- The first render runs before `render_effect` returns, and it is also the
  dependency collection: every signal the template reads subscribes the
  effect.
- A write to a read signal re-renders the same instance and the block gets
  the new HTML. An equal write (by the signal's `==`) neither re-renders nor
  calls the block.
- The call returns the `Hibiki::Effect`. Inside `Hibiki.root` or another
  effect the owner tree adopts it and disposes it with its owner, which is
  what a channel does; a bare caller like this script calls `dispose` itself.
- A component without `#rerender` raises `ArgumentError`
  (`TodoList has no #rerender — include Hibiki::Phlex::Rerenderable`), because
  the render always happens on the instance you passed in.
- `scheduler:` passes straight through to `Hibiki::Effect`; see
  [Deferring re-renders](#deferring-re-renders).

## In a Rails channel

With `hibiki_rails`, the channel builds the graph when the browser subscribes
and disposes it when the browser leaves. Create the component in
`build_graph`, wrap it in a render effect, and send the HTML down the channel's
own subscription:

```ruby
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @list = TodoList.new
    Hibiki::Phlex.render_effect(@list) { |html| transmit({ html: }) }
  end

  # Public methods are actions the page can call.
  def add(data) = @list.add(data["title"])
end
```

The first run transmits the initial HTML, and the packaged client replaces the
element whose id matches the fragment's root (`todos`). Each action writes a
signal, the effect re-runs, the same element is replaced again. The effect
belongs to the channel's root, so it is disposed when the browser
unsubscribes.

The page renders the component once as a placeholder inside an island, an
element that subscribes to the channel and whose descendants can call its
actions. A second component wraps it so any page can `render TodoListIsland.new`:

```ruby
class TodoListIsland < Phlex::HTML
  include Hibiki::Rails::Helpers

  def view_template
    div(**hibiki_island(TodosChannel, cid: SecureRandom.uuid)) do
      render TodoList.new

      form(**on(:add, event: :submit)) do
        input(type: "text", name: "title", placeholder: "new todo")
        button { "add" }
      end
    end
  end
end
```

`hibiki_island` and `on` each return a `{ data: { ... } }` hash, so splat them
into the element. Use `hibiki_island` here and not `island`, because `island`
is the ERB block helper and raises `ArgumentError` outside ActionView. The
placeholder `TodoList.new` is a throwaway; the channel's long-lived instance
takes over from its first transmit. Put controls inside the reactive component
the same way: include `Hibiki::Rails::Helpers` there and write
`button(**on(:toggle, with: { index: }))`. The `on` option table lives in the
`hibiki-rails` skill.

## The generator

```sh
bin/rails g hibiki:rails:phlex NAME
```

Writes three files: `CounterChannel` in `app/channels` (transmit transport,
one `increment` action delegating to the component), `Components::Counter` in
`app/components/counter.rb` (the reactive component, `state :count, 0` and
`derived(:doubled)`), and `Components::CounterIsland` next to it (the island
wrapper). Render it anywhere with `<%= render Components::CounterIsland.new %>`.
The generator warns and still writes when `hibiki_phlex` is missing, so the
scaffold can come first, and prints a hint when the one-time
`bin/rails g hibiki:rails:install` has not run. See
[references/generators.md](references/generators.md) for the emitted shape.

## Transmit or broadcast

Transmit is the default for Phlex: the HTML rides the channel's own
subscription, and no Turbo stream is involved. The other route is a Turbo
broadcast, with `turbo_stream_from` inside the island and a broadcast helper
in the block:

```ruby
Hibiki::Phlex.render_effect(@list) do |html|
  broadcast_replace target: "todos", html:
end
```

Broadcasts give you Turbo's stream actions such as morphing, and carry an
ordering trap around the first update that transmit does not: the stream must
be connected before the first broadcast or the placeholders stay forever. The
two-routes comparison and that trap live in the `hibiki-rails` skill.

## Granularity

One effect covers one component, so a change to any signal the template read
re-renders the whole component. For smaller updates, split the page into
smaller components and give each its own render effect; a channel may hold
several.

## Deferring re-renders

`render_effect` accepts `scheduler:` and passes it to the effect. `hibiki_rails`
ships `Debounce`, which merges a burst of changes into one render per window:

```ruby
scheduler = Hibiki::Rails::Debounce.new(actor: graph_actor, wait: 0.2)

Hibiki::Phlex.render_effect(@list, scheduler:) { |html| transmit({ html: }) }
```

Within one action the channel already merges every write into a single
render, so a debounce only pays off across actions: many quick actions, or a
burst of database pings, should mean one render rather than one each. The
first render is never deferred, because that run collects the dependencies.

## ActiveRecord

A component that shows records uses the same pattern as an ERB partial: an
`after_commit` callback pings a signal and the component loads records inside
the graph, on the channel's thread. Load the `hibiki-rails` skill and open its
`working-with-active-record` reference.

## Why the Phlex pin is strict

A Phlex component renders once; a second call raises
`Phlex::DoubleRenderError`. Phlex 2 records that an instance has rendered in a
single private instance variable, `@_state`, and keeps everything else about a
render per call. `Rerenderable#rerender` clears that variable and calls the
component again, and that is the entire adapter.

It leans on a private implementation detail, so the gem guards it twice: the
gemspec allows only tested Phlex minors (`>= 2.4, < 2.5`), and a contract spec
exercises the Phlex behavior directly. Raising the bound with Phlex's internals
moved fails that spec in CI instead of failing in your app. Do not loosen the
pin in your own Gemfile to get a newer Phlex; wait for a hibiki_phlex release
that re-verifies the contract.

## Not the scaffold's --phlex

Two Phlex idioms live in this project. Pick by who owns the state:

| | `hibiki_phlex` (this skill) | scaffold `--phlex` |
|---|---|---|
| State lives in | the component (`Hibiki::Reactive`) | the channel (signals) |
| Component is | long-lived, one instance per subscription | stateless view, new instance per render |
| Includes | `Hibiki::Reactive`, `Rerenderable` | nothing from hibiki |
| Re-rendered by | `Hibiki::Phlex.render_effect` | the channel, `broadcast_replace renderable:` |
| Locals arrive as | signal reads | keyword arguments to `initialize` |
| Files under | `app/components/` (`Components::`) | `app/views/` (`Views::`, via `phlex:install`) |
| Gem needed | `hibiki_phlex` | `phlex-rails` only |

The scaffold's `--phlex` is the ERB scaffold with a different view layer, and
`hibiki_phlex` is not involved; load `hibiki-rails-scaffold` for it.

## Pitfalls

- Passing a component without `Rerenderable` to `render_effect`. It raises
  `ArgumentError` naming `#rerender`, since the render runs on the same
  instance every time. (phlex-support)
- Creating a new component per render. The signals live in the instance, so a
  fresh one starts from every default; keep one instance per subscription and
  treat the island's placeholder as throwaway. (phlex-support)
- A root element without a page-unique id. The transmitted fragment's root id
  is the swap key the client matches, so a missing or duplicated id updates
  nothing or the wrong element. (generators)
- A positional mutable default such as `state :items, []`. One array is shared
  by every instance; use the block form. (mutable-defaults)
- Mutating a signal's value in place. The write compares by `==` and an array
  pushed onto is equal to itself, so nothing re-renders; build a new value and
  assign it. (mutable-defaults)
- Expecting a derived to recompute on the write. It is lazy and recomputes on
  the next read, so read it in the template or an effect. (class-based-reactivity)
- Writing signals from another thread. The channel confines the graph to its
  own actor thread, so route outside changes through an `after_commit` ping
  and an action or channel hook. (working-with-active-record)
- Loosening the Phlex pin. `Rerenderable` clears Phlex's private `@_state`,
  which only the allowlisted minors are verified to use that way. (phlex-support)
- Expecting `hibiki_phlex` to bring `phlex-rails`. It depends on `hibiki` and
  `phlex` only, so add `phlex-rails` to render components from views.
  (phlex-support)
- Calling `island` in a Phlex component. It is ERB-only and raises; use
  `div(**hibiki_island(channel, cid:))`. (the-js-client)
- Adding `Rerenderable` or `Hibiki::Reactive` to a scaffold `Views::`
  component. Those are stateless views the channel re-renders with
  `renderable:`, a new instance each time, so the includes do nothing. (crud-notes)
- Using `broadcast_replace` without `turbo_stream_from` inside the island.
  The broadcast route needs the stream source, and the first broadcast is lost
  unless the stream is connected before the channel subscribes. (rails-usage)
- Reaching for `Debounce` to merge writes within one action. The channel
  already batches those; a debounce only helps across actions. (phlex-support)
- Forgetting to dispose a bare render effect. Outside a root or another
  effect nothing owns it, so it keeps its subscriptions until `dispose`. (phlex-support)
- Writing `Phlex::HTML` inside `module Hibiki`. There the bare constant
  resolves to `Hibiki::Phlex`, so write `::Phlex::HTML`. (phlex-support)

## Reference files

- [references/phlex-support.md](references/phlex-support.md): API table,
  component recipe, channel and island wiring, routes, Debounce, the pin, the
  `--phlex` contrast; open for any question about a reactive Phlex component.
- [references/generators.md](references/generators.md): what
  `hibiki:rails:phlex` emits and how to render it; open when generating or
  reshaping the generated files.

## Related skills

- `hibiki`: the signal core (state, derived, effect, batch, root, Reactive).
- `hibiki-rails`: channels, transports, the JS client, ActiveRecord patterns.
- `hibiki-rails-forms`: `ReactiveForm` and live edit forms.
- `hibiki-rails-scaffold`: the CRUD scaffold, including its `--phlex` flag.
- `hibiki-rails-motion`: transitions and motion for updated fragments.
