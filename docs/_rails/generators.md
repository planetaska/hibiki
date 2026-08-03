---
title: Generators
nav_order: 3
---

# Generators

`hibiki_rails` comes with batteries included. Each supported shape has a generator that scaffolds it as a *working* mini-example — one state, one derived, one action, one effect. Run a generator, render the output from any page, click `+1`, watch it live-update. The generated files are meant to be reshaped in place.

This page covers the three **component-shape** generators, which give you one small island to grow from. If what you want is a whole resource — a live index with search, filtering, sorting and pagination, plus edit in place — reach for [CRUD scaffolding]({{ "/crud-scaffolding/" | relative_url }}) instead.

## Stimulus shape

Stock Stimulus vocabulary (`data-controller` / `data-action`) over the Turbo-broadcast transport — you own a small Stimulus controller per component.

```sh
bin/rails g hibiki:rails:stimulus NAME [VIEW_PATH]
```

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

The same Turbo-broadcast transport, but the gem's packaged generic controller drives the island — no per-component JS at all. The view is stamped through the `hibiki_island` / `on` helpers (see [The JS client]({{ "/the-js-client/" | relative_url }})).

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

The component owns the state, the channel owns the transport: a render effect re-renders the component and transmits its HTML over the channel's own subscription — no Turbo Streams involved (see [Phlex support]({{ "/phlex-support/" | relative_url }})).

```sh
# requires the hibiki_phlex gem
# (and phlex-rails, to render components from views)
bin/rails g hibiki:rails:phlex NAME
```

Generates:

1. A minimal channel in `app/channels`
2. A minimal Phlex component set (two files) in `app/components`

Phlex component example:

```ruby
class Components::Counter < Phlex::HTML
  state :count, 0
  derived(:doubled) { count * 2 }

  def view_template
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

`VIEW_PATH` is the views directory under `app/views` (it defaults to `NAME`). The emitted partial is self-contained, so rendering it — `<%= render "counter/counter" %>`, or `<%= render Components::CounterIsland.new %>` for the Phlex shape — is the only line a page needs.

The `stimulus` shape works with zero extra wiring; `island` and `phlex` need the one-time `hibiki:rails:install` (they print a hint when it's missing). Namespaced names work too: `admin/counter` pins the channel class via `static channel` in the generated controller, since the Stimulus identifier can't infer it. And in apps without an importmap (jsbundling/vite), where `controllers/index.js` has no eager loader, the `stimulus` generator appends the controller's import/register pair to it — in the exact format `stimulus:manifest:update` emits, so a later manifest update keeps it.
