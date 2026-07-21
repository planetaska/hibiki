---
title: The JS client
nav_order: 5
---

# The JS client

The gem vendors its own JavaScript, turbo-rails-style: the engine puts `hibiki.js` on the app's asset path and merges the `"hibiki-rails"` pin into the import map, so importmap-rails apps have no install step beyond registering the controller. `bin/rails g hibiki:rails:install` does that (plus the `Helpers` include below, the `ApplicationCable` boilerplate, and the `@rails/actioncable` pin — a stock app has neither until its first `rails g channel`), or create the one-line shim yourself:

```js
// app/javascript/controllers/hibiki_controller.js
export { default } from "hibiki-rails" // registers as "hibiki" — the helpers hardcode that identifier
```

The registration is a file-backed shim on purpose: importmap apps eager-load it from the controllers directory, jsbundling apps get the matching import/register pair in `controllers/index.js` (the install generator appends it), and because it is derived from a real controller file, `bin/rails stimulus:manifest:update` regenerates it instead of dropping it.

For jsbundling/vite apps, `npm install hibiki-rails` — the [npm package](https://www.npmjs.com/package/hibiki-rails) is the same module the engine vendors, and pulls in `@rails/actioncable`. It is released in lockstep with the gem:

| `hibiki_rails` gem | `hibiki-rails` npm | notes |
| ------------------ | ------------------ | ----- |
| 0.1.0              | 0.1.0              | initial release |

## Islands and helpers

The client is one generic Stimulus controller that drives any *island*: a DOM subtree bound to one channel subscription. Islands are stamped with the opt-in `Hibiki::Rails::Helpers` — include it where you want the bare names (`ApplicationHelper` for ERB, individual Phlex components); the gem never includes it for you:

```erb
<%= tag.div(**hibiki_island(TodosChannel, cid: @cid)) do %>
  <%= render TodoList.new %>  <%# placeholder; replaced by DOM id %>
  <%= tag.form(**on(:add, event: :submit)) do %>
    <input type="text" name="title">
    <button>add</button>
  <% end %>
<% end %>
```

- `hibiki_island(channel, cid:)` — the island root: one subscription, identified by the page's `cid`.
- `on(action, event:, with:)` — forward a DOM event (`:click` default, `:change`, `:submit`) as a channel action, with `with:` as its payload. A changed control also sends `{ name => value }`; a submitted form sends its FormData and is reset after performing.
- `reactive(name, placeholder)` / `reactive_attrs(name)` — placeholder for a single reactive value, paired with the channel's `transmit_value` (see [Reactive values]({{ "/reactive-values/" | relative_url }})).

## The transmit transport

Transport is the channel's own subscription in both directions: render effects call `transmit({ html: })` and the client swaps each fragment in by its root DOM id (`Hibiki::Phlex.render_effect` pairs naturally):

```ruby
def build_graph
  @list = TodoList.new
  Hibiki::Phlex.render_effect(@list) { |html| transmit({ html: }) }
end
```

Because the client registers its `received` callback at subscribe time — before the server ever runs `build_graph` — the effects' first transmits always land: no Turbo stream, no connected-wait, and the server-rendered initial HTML is only a paint-avoidance placeholder. One rule carries over from any replace-fragment design: never transmit a fragment containing the input the user is currently typing in.
