---
title: Generators
nav_order: 3
---

# Generators

`hibiki_rails` comes battery included. Each supported shape has a generator that scaffolds it as a *working* mini-example — one state, one derived, one action, one effect. Run a generator, render the output from any page, click `+1`, watch it live-update. They are meant to be reshaped in place.

## Stimulus shape generator

```sh
bin/rails g hibiki:rails:stimulus NAME [VIEW_PATH]
```
Generates:

1. One minimal channel in `/app/channels`
2. One minimal Stimulus ChannelController in `/app/javascript/controllers`
3. One minimal view partial set (two files) in `/app/views/[VIEW_PATH]`

Partial example:

```erb
<% cid = local_assigns.fetch(:cid) { SecureRandom.uuid } %>
<div data-controller="counter" data-counter-cid-value="<%= cid %>">
  <%= turbo_stream_from "counter", cid %>

  <%= render "counter/counter_display", count: 0, doubled: 0 %>

  <p><button data-action="counter#increment">+1</button></p>
</div>
```

## Island shape generator

```sh
bin/rails g hibiki:rails:island NAME [VIEW_PATH]
```

Generates:

1. One minimal channel in `/app/channels`
2. One minimal view partial set (two files) in `/app/views/[VIEW_PATH]`

Partial example:

```erb
<% cid = local_assigns.fetch(:cid) { SecureRandom.uuid } %>
<%= tag.div(**hibiki_island(CounterChannel, cid:)) do %>
  <%= turbo_stream_from "counter", cid %>

  <%= render "counter/counter_display", count: 0, doubled: 0 %>

  <p><%= tag.button("+1", **on(:increment)) %></p>
<% end %>
```

## Phlex shape generator

```sh
# requires hibiki_phlex gem
bin/rails g hibiki:rails:phlex NAME
```

Generates:

1. One minimal channel in `/app/channels`
2. One minimal Phlex component set (two files) in `/app/commponents/[NAME]`

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

## Rendering generated reactive partial

`VIEW_PATH` is the views directory under `app/views` (defaults to `NAME`); the emitted partial is self-contained, so simply rendering the partial `<%= render "counter/counter" %>` — or `<%= render Components::CounterIsland.new %>` for the Phlex shape — is the only line a page needs.

The `stimulus` shape works with zero wiring; `island` and `phlex` need the one-time `hibiki:rails:install` (they print a hint when it's missing). Namespaced names work (`admin/counter` pins `static channel` where the Stimulus identifier can't infer it). In apps without an importmap (jsbundling/vite), where `controllers/index.js` has no eager loader, the `stimulus` generator also appends the controller's import/register pair to it — and even survives `stimulus:manifest:update`.
