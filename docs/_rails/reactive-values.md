---
title: Reactive values
nav_order: 7
---

# Reactive values

When all you want on the wire is one derived (or state) value — not a whole partial or component — you can skip the fragment entirely. The view paints named placeholders, and the channel keeps them fresh:

```erb
<!-- Display a single reactive value anywhere in the view -->
<h1>todos (<%= reactive :remaining, 0 %> left)</h1>
...
<!-- Even across multiple places -->
<p>remaining: <%= reactive :remaining, 0 %></p>
```

```ruby
# By adding a single transmit_value line in the channel
def build_graph
  @list = TodoList.new
  transmit_value(:remaining) { @list.remaining }
end
```

`reactive(name, placeholder = "", tag_name: :span)` emits `<span data-hibiki-value="remaining">0</span>`; `transmit_value` wraps the block in an effect that transmits the fresh value whenever a signal the block reads changes, and the client writes it into **every** placeholder carrying that name — like styling by class name, one value may appear any number of times, anywhere on the page (including outside the island, e.g. a header badge). The name joins the two halves and must be page-unique across channels. Each placeholder keeps its own tag, classes, and attributes across updates (only its text changes), so different sites can style the same value differently. In Phlex components, stamp the placeholder yourself by splatting the attributes: `span(**reactive_attrs(:remaining)) { "0" }`.

This is transport- and shape-agnostic: `transmit_value` always uses the channel's own `transmit`, which every `ChannelController` handles — so it works the same whether the page runs the generic packaged controller or a `ChannelController` subclass, and it composes with a page whose other fragments ride Turbo broadcasts: one channel can serve a fragment over broadcast and a value over transmit at the same time. A subclass that overrides `received` should call `super` (or handle the `value` message itself) to keep reactive values live.

Cost and caveats: this is cheap — it rides the island's existing subscription and controller (no new Stimulus instance, no new channel), adding just one server-side effect and a tiny payload per value. Values are text, never markup — the client assigns `textContent`, so nothing is interpreted as HTML; for markup, use a fragment. And when several values always change together, one partial/component fragment beats N spans.

The `data-hibiki-*` attributes the helpers emit are a private contract with the vendored JS — they version together; don't hand-write them in app code. The protocol does have a **client-written half**, though: `data-hibiki-busy` and `data-hibiki-state` are stamped at runtime by the client and no helper emits them. Those your app is meant to *read* — from CSS — and still never to write. See [loading and connection state]({{ "/the-js-client/" | relative_url }}).

The helper interface's shape is inspired by [phlex-reactive](https://phlex-reactive.zoolutions.llc)'s `on(...)` actions.
