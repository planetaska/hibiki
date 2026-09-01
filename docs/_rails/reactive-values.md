---
title: Reactive values
nav_order: 6
---

# Reactive values

When all you want on the wire is one derived (or state) value — you can skip the fragment entirely. The view renders named placeholders, and the channel keeps them fresh:

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

### Usage

A reactive value has two halves. The view half is the `reactive` helper:

```ruby
reactive(name, placeholder = "", tag_name: :span)
```

It emits a named placeholder in plain HTML:

```html
<span data-hibiki-value="remaining">0</span>
```

The channel half is `transmit_value(name) { ... }`. It wraps the block in an effect: whenever a signal the block reads changes, the channel transmits the fresh value, and the client writes it into **every** placeholder carrying that name. Like styling by class name, one value may appear any number of times, anywhere on the page — including outside the island (for example, a badge in navigation).

The name joins the two halves, so it must be page-unique across channels. Each placeholder keeps its own tag, classes and attributes across updates — only its text changes — so different sites can style the same value differently. In Phlex components, add the attributes yourself by splatting them: `span(**reactive_attrs(:remaining)) { "0" }`.

Reactive values are transport- and shape-agnostic. `transmit_value` always uses the channel's own `transmit`, which every `ChannelController` handles, so it works the same whether the page runs the generic packaged controller or a `ChannelController` subclass. It also composes with a page whose other fragments ride Turbo broadcasts: one channel can serve a fragment over broadcast and a value over transmit at the same time. A subclass that overrides `received` should call `super` (or handle the `value` message itself) to keep reactive values live.

Reactive values are cheap: they ride the island's existing subscription and controller — no new Stimulus instance, no new channel — adding just one server-side effect and a tiny payload per value. Two caveats. Values are text, never markup: the client assigns `textContent`, so nothing is interpreted as HTML — for markup, use a fragment. And when several values always change together, one partial/component fragment beats N spans.

## The URL sibling: `transmit_url`

`transmit_url` is `transmit_value` for the address bar — one per channel, mirroring graph state into the URL:

```ruby
def build_graph
  # ... signals, deriveds, effects ...

  transmit_url do
    if (id = @editing_id.value) && @rows.value.any? { it.id == id }
      urls.edit_song_path(id)
    else
      urls.songs_path(**query_url_params)   # canonical params, defaults omitted
    end
  end
end

private

def urls = ::Rails.application.routes.url_helpers
```

The block runs as an equality-gated effect: whenever a signal it reads changes, the channel transmits `{ url: }` and the client `history.replaceState`s the bar to it. Always `replaceState`, never `pushState` — **the URL is a mirror of graph state, not a history entry**. There is no popstate choreography to get wrong, and Back leaves the page normally instead of stepping through every search keystroke. Same-origin only: the client resolves the URL against the page's own origin and refuses anything else.

The mirror pays off when the URL comes *back*: a reload, or a link someone shared, should land on the state it names. That needs the controller to render the initial page from the same params and the island to seed the channel with them at subscribe time — the loop the generated scaffold wires end to end ([CRUD scaffolding]({{ "/crud-scaffolding/" | relative_url }})). A form's URL is worth mirroring too, as above: reloading mid-edit lands on the standard edit page.
