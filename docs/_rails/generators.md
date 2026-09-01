---
title: Generators
nav_order: 3
---

# Generators

`hibiki_rails` comes with batteries included. Each supported shape has a generator that scaffolds it as a *working* mini-example — one state, one derived, one action, one effect. Run a generator, render the output from any page, click `+1`, watch it live-update. The generated files are yours to reshape in place.

This page covers the three **component-shape** generators, which give you one small reactive component to grow from. If you want a whole resource — a live index with search, filtering, sorting and pagination, plus create and edit in place — reach for [CRUD scaffolding]({{ "/crud-scaffolding/" | relative_url }}) instead.

## Stimulus shape

The `stimulus` shape speaks stock Stimulus vocabulary (`data-controller` / `data-action`) over the Turbo-broadcast transport; you own a small Stimulus controller per component.

```sh
bin/rails g hibiki:rails:stimulus NAME [VIEW_PATH]
```

`VIEW_PATH` is the directory under `app/views` that receives the partials. If no path is provided, the partials will land in a directory named after `NAME`.

Generates:

1. A minimal channel in `app/channels`
2. A minimal Stimulus `ChannelController` subclass in `app/javascript/controllers`
3. A minimal view partial set (two files) in `app/views/[VIEW_PATH]`

Partial example:

```erb
<% cid = local_assigns.fetch(:cid) { SecureRandom.uuid } %>
<div data-controller="counter" data-counter-cid-value="<%= cid %>">
  <%= turbo_stream_from "counter", cid %>

  <%= render "counter/counter_display", count: 0, doubled: 0 %>

  <p><button data-action="counter#increment">+1</button></p>
</div>
```

## Island shape

The `island` shape uses the same Turbo-broadcast transport, but the gem's packaged generic controller drives the island — you write **no per-component JS** at all. The `hibiki_island` / `on` helpers add the `data-*` attributes to the view (see [The JS client]({{ "/the-js-client/" | relative_url }})).

```sh
bin/rails g hibiki:rails:island NAME [VIEW_PATH]
```

Generates:

1. A minimal channel in `app/channels`
2. A minimal view partial set (two files) in `app/views/[VIEW_PATH]`

Partial example:

```erb
<% cid = local_assigns.fetch(:cid) { SecureRandom.uuid } %>
<%= tag.div(**hibiki_island(CounterChannel, cid:)) do %>
  <%= turbo_stream_from "counter", cid %>

  <%= render "counter/counter_display", count: 0, doubled: 0 %>

  <p><%= tag.button("+1", **on(:increment)) %></p>
<% end %>
```

## Phlex shape

In the `phlex` shape, the component owns the state and the channel owns the transport: a render effect re-renders the component and transmits its HTML over the channel's own subscription — no Turbo Streams involved (see [Phlex support]({{ "/phlex-support/" | relative_url }})).

```sh
# requires the hibiki_phlex gem
# (and phlex-rails, to render components from views)
bin/rails g hibiki:rails:phlex NAME
```

Generates:

1. A minimal channel in `app/channels`
2. Two Phlex components in `app/components` — the reactive component itself
   (`Components::Counter`), and an island wrapper (`Components::CounterIsland`)
   that renders it inside a subscription so any page can drop it in with one line

Phlex component example:

```ruby
class Components::Counter < Phlex::HTML
  include Hibiki::Reactive              # per-instance signals
  include Hibiki::Phlex::Rerenderable   # lets the render effect re-render this instance
  include Hibiki::Rails::Helpers        # emits the client's data attributes

  state :count, 0
  derived(:doubled) { count * 2 }

  def view_template
    # The root id is the swap key for transmitted fragments — page-unique.
    div(id: "counter") do
      p { "count: #{count} · doubled: #{doubled}" }
      button(**on(:increment)) { "+1" }
    end
  end

  def increment
    self.count += 1
  end
end
```

## Rendering the generated component

The generated partial is self-contained, so any page can render it with one line:

```erb
<%= render "counter/counter" %>

<% # Or if you use Phlex: %>
<%= render Components::CounterIsland.new %>
```

The partial path is the view path followed by the name, so `counter` generated with the default view path renders as `counter/counter`. Phlex components take no view path: they live in `app/components` and render by class.

The `stimulus` shape works with zero extra wiring; `island` and `phlex` need the one-time `hibiki:rails:install` (they print a hint when it's missing).

Namespaced names work in every shape: `admin/counter` nests the channel, the view path and the component the way Rails would. In the `stimulus` shape the generated controller also pins the channel class via `static channel`, since the Stimulus identifier cannot infer a namespaced one.
