---
title: Rails usage
nav_order: 5
---

# Rails usage

The generators hand you a working component. This page shows what is
inside one, so you can write a channel of your own or reshape a generated
one with confidence. It builds the counter from the quick start by hand,
piece by piece: the channel, the view, and the JavaScript that joins them.

A short orientation first, for readers new to signals. Hibiki has three
building blocks. A *state* holds a value. A *derived* computes a value from
other signals and stays current as they change. An *effect* is a block that
runs once, remembers which signals it read, and runs again whenever one of
them changes. In a hibiki_rails app all three live on the server, and the
effects render HTML. The signals and effects one page uses together make
up its *graph*. An ActionCable channel owns the graph: it builds one when a
browser tab subscribes and discards it when the tab leaves, so every tab
has a graph of its own. The
[core introduction]({{ "/introduction/" | relative_url }}) shows the three
building blocks in a dozen lines of plain Ruby, and the
[Rails introduction]({{ "/rails-introduction/" | relative_url }}) walks
through the round trip a click makes.

## The channel

A reactive channel is an ordinary ActionCable channel that includes
`Hibiki::Rails::Channel`. You write two things: a `build_graph` method
that creates the signals and effects, and one public method for each
action the browser may call.

```ruby
# app/channels/counter_channel.rb
class CounterChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @count = Hibiki::State.new(0)
    @step  = Hibiki::State.new(1)
    doubled = Hibiki::Derived.new { @count.value * 2 }

    Hibiki::Effect.new do
      broadcast_replace target: "count", partial: "counter/count",
                        locals: { count: @count.value, doubled: doubled.value }
    end
    Hibiki::Effect.new do
      broadcast_replace target: "step", partial: "counter/step",
                        locals: { step: @step.value }
    end
  end

  def increment = @count.value += @step.value
  def burst     = 10.times { @count.value += 1 }

  def set_step(data)
    @step.value = Integer(data["step"])
  end
end
```

`build_graph` runs once, when the browser subscribes. Keep the signals in
instance variables so the actions can reach them. `doubled` is a local
because only the effect reads it.

Each effect here is a *render effect*: it renders a partial and sends the
result to the browser. An effect runs as soon as it is created. That first
run reads `@count.value` and `doubled.value`, and each read subscribes the
effect to that signal. From then on, every change to `@count` re-runs the
first effect, which renders the partial again and sends the replacement.
The second effect read only `@step`, so a change to `@count` leaves it
alone. You never declare which effect depends on which signal. The reads
decide.

`broadcast_replace` is one of the helpers the include brings in. It renders
the partial and tells the page to replace the element whose DOM id is
`target` with the result. [Broadcast helpers]({{ "/broadcast-helpers/" | relative_url }})
describes the rest, including a morph variant that keeps focus and scroll
position through an update.

## Actions

Every public method on the channel is an action, and the browser calls it
by name. Anything the browser must not call goes under `private`. The
include hides `build_graph`, `subscribed`, and `unsubscribed` from the
browser for you.

An action changes the graph by writing signals, and does nothing else. It
never renders. The effects that read those signals notice the change and
re-render on their own, so `increment` is a one-line write and the page
still updates.

The whole action body runs inside one *batch*. Writes land immediately,
but effect re-runs wait until the action returns, and each affected effect
then runs once. `burst` writes `@count` ten times and produces one
re-render, not ten. Writing a value equal to the current one changes
nothing and re-renders nothing, so an action that leaves the graph as it
found it sends no HTML at all.

An action method with one parameter receives the browser's payload as a
hash with string keys, as `set_step` does. Which keys arrive depends on how
the view sends the action; the next section shows both ways.

Actions do not run on ActionCable's worker threads. Each graph has a thread
of its own, and the channel runs actions there one at a time, in the order
they arrived. This is what lets the core gem work without locks. One
consequence is worth knowing early: `current_user` from the connection
works inside an action, but anything you set on a `Current` attribute is
gone by the next one. [Channel lifecycle]({{ "/channel-lifecycle/" | relative_url }})
follows a subscription from open to close and explains why.

## The view

The view has three parts: a container whose JavaScript opens the
subscription, a stream the browser listens on for HTML, and the fragments
the effects replace.

This example is the Stimulus shape. We also provide helpers that make the markup less verbose. Keep reading to see the other styles.
{: .tip }

```erb
<%# app/views/counter/_counter.html.erb %>
<% cid = local_assigns.fetch(:cid) { SecureRandom.uuid } %>
<div data-controller="counter" data-counter-cid-value="<%= cid %>">
  <%= turbo_stream_from "counter", cid %>

  <%# Placeholders: the graph's first run replaces both. %>
  <%= render "counter/count", count: 0, doubled: 0 %>
  <%= render "counter/step", step: 1 %>

  <p>
    <button data-action="counter#increment">+1</button>
    <button data-action="counter#burst">+10</button>
    <input type="number" name="step" value="1"
           data-action="change->counter#setStep">
  </p>
</div>
```

```erb
<%# app/views/counter/_count.html.erb %>
<%# locals: (count:, doubled:) -%>
<p id="count">count: <%= count %> · doubled: <%= doubled %></p>
```

The [stimulus generator]({{ "/generators/#stimulus-shape" | relative_url }}) produces this shape. The fragment's root element carries `id="count"`, and the effect names the same id in `target:`. That id is the only link between the two. A typo fails silently, because the browser has nothing to replace.

### The page-load id

`cid` is a per-page-load id. The browser sends it when it opens the
subscription, and the channel requires one; a subscription without a
`cid` is rejected. It is what gives each tab its own graph: two tabs
showing the same page generate two ids, subscribe twice, and never share
state. The partial above makes one with `SecureRandom.uuid` unless the
page that renders it passes `cid:` in.

The channel broadcasts to the stream named by `[channel_name, cid]`, which
for `CounterChannel` is `["counter", cid]`. That is exactly what
`turbo_stream_from "counter", cid` listens on, so the two sides meet. If a
page listens on different streams, override `stream_name` on the channel;
if the id should come from somewhere other than the subscription params,
override `cid`.

### The Stimulus controller

```js
// app/javascript/controllers/counter_controller.js
import { ChannelController } from "hibiki-rails"

export default class extends ChannelController {
  setStep(event) {
    this.perform("set_step", { step: event.target.value })
  }
}
```

The base class does the work. When the element connects, it opens a
subscription to `CounterChannel`, inferring the class name from the
controller identifier `counter`, and sends the `cid` along. Set
`static channel = "Admin::CounterChannel"` when the names do not line up.
Plain `data-action` tokens such as `counter#increment` are forwarded as
channel actions with no payload, so most actions need no method at all.
Declare one only when the action needs a payload, and send it with
`perform(name, payload)`.

### The same view without a controller of your own

The gem also ships one generic controller that drives any container, so
**you can skip the per-component JavaScript entirely**. Two view helpers add
the attributes it reads: `hibiki_island` on the container, and `on` on each
control that sends an action.

```erb
<%# no new Stimulus controller is needed for this container %>
<%= tag.div(**hibiki_island(CounterChannel, cid:)) do %>
  <%= turbo_stream_from "counter", cid %>

  <%= render "counter/count", count: 0, doubled: 0 %>
  <%= render "counter/step", step: 1 %>

  <p>
    <%= tag.button("+1", **on(:increment)) %>
    <%= tag.button("+10", **on(:burst)) %>
    <%= tag.input(type: "number", name: "step", value: 1,
                  **on(:set_step, event: :change)) %>
  </p>
<% end %>
```

A changed control sends its value under its own `name`, so `set_step`
receives `data["step"]` here too, and the channel is unchanged. The
[island generator]({{ "/generators/#island-shape" | relative_url }}) produces this shape.

Since 0.12.0, the `island` helper writes those first three lines for you:
it generates the cid, stamps the container, and derives the
`turbo_stream_from` line from the channel class.
{: .tip }

With the `island` helper, the same view becomes:

```erb
<%= island CounterChannel do %>
  <%= render "counter/count", count: 0, doubled: 0 %>
  <%= render "counter/step", step: 1 %>

  <p>
    <%= tag.button("+1", **on(:increment)) %>
    <%= tag.button("+10", **on(:burst)) %>
    <%= tag.input(type: "number", name: "step", value: 1,
                  **on(:set_step, event: :change)) %>
  </p>
<% end %>
```

Both forms emit the same markup. `hibiki_island` remains the primitive. [The JS client]({{ "/the-js-client/" | relative_url }})
covers the helpers in full, including debouncing, confirmation dialogs,
and falling back to a link's or form's native behavior when the connection
is down.

## Two routes for the HTML

Rendered HTML can reach the page two ways. The example so far uses Turbo
broadcasts: the effect renders a Turbo Stream, broadcasts it to the named
stream, and Turbo's own JavaScript applies it. The other route is
*transmit*: the effect hands the HTML down the channel's own subscription,
and the packaged client replaces each element whose DOM id matches the
fragment's root. No Turbo stream is involved, so the view drops its
`turbo_stream_from` line and is otherwise the same island. With the
`island` helper, `transport: :transmit` does the same.

```erb
<%= tag.div(**hibiki_island(CounterChannel, cid:)) do %>
  <%= render "counter/count", count: 0, doubled: 0 %>
  <%= render "counter/step", step: 1 %>

  <p>
    <%= tag.button("+1", **on(:increment)) %>
    <%= tag.button("+10", **on(:burst)) %>
    <%= tag.input(type: "number", name: "step", value: 1,
                  **on(:set_step, event: :change)) %>
  </p>
<% end %>
```

On the channel side, the effect calls `transmit` instead of a broadcast
helper:

```ruby
Hibiki::Effect.new do
  transmit({ html: ApplicationController.render(
    partial: "counter/count",
    locals: { count: @count.value, doubled: doubled.value }
  ) })
end
```

So the route the channel takes decides whether the view needs the stream
line:

| Channel renders with | `turbo_stream_from` inside the island |
| -------------------- | ------------------------------------- |
| `broadcast_replace`, `broadcast_morph`, `broadcast_refresh` | yes |
| `transmit({ html: })` / `transmit_value` | no |

Both controllers above handle both routes, and one channel may use both
at once. Broadcasts give you Turbo's own stream actions, which is where
morph and whole-page refresh live. Transmit has fewer moving parts and is
the route the Phlex render effect uses, as
[Phlex support]({{ "/phlex-support/" | relative_url }}) shows.
[Does an island need a Turbo stream?]({{ "/the-js-client/#does-an-island-need-a-turbo-stream" | relative_url }})
in The JS client has the details of both island shapes.

## Placeholders and the first update

The partials the page renders at load are placeholders. The graph's effects
run for the first time right after the browser subscribes, and their first
output replaces the placeholders within a moment of the page appearing. So
a placeholder does not have to match the graph's initial state, though
rendering the same values, as the example does, spares the reader a visible
jump.

The broadcast route has an ordering trap here. `turbo_stream_from` opens a
subscription of its own, separate from the channel's, and a broadcast
reaches the page only once that stream has confirmed. If the channel
subscribes first, the effects' first run broadcasts into a stream nobody
is listening on yet, the HTML is lost, and the placeholders stay forever.
The packaged `ChannelController` avoids the trap: before it subscribes, it
finds the stream source inside its element and waits for Turbo to mark it
connected. Both generated shapes inherit that behavior. Only a client
written from scratch has to do the waiting itself, with the exported
helper:

```js
import { streamConnected } from "hibiki-rails"

await streamConnected(element.querySelector("turbo-cable-stream-source"))
consumer.subscriptions.create({ channel: "CounterChannel", cid }, {})
```

The transmit route has no such trap. The client starts listening the
moment it subscribes, before the server runs `build_graph`, so the first
transmit always lands.

## Rendering without a request

A partial rendered from a channel is rendered outside any request. There
is no controller, so `params` and `session` are empty, `action_name` is
nil, and instance variables a controller would have set do not exist.
Nothing raises; a partial that reads `@book` renders a blank, and one that
branches on `action_name` takes the other branch forever. Pass everything
the partial needs through `locals:`, and declare them with a strict-locals
header as `_count.html.erb` does, so a forgotten local raises at render
time. [Broadcast helpers]({{ "/broadcast-helpers/" | relative_url }})
covers this in more depth.

## Where to go next

- [Reactive values]({{ "/reactive-values/" | relative_url }}) sends a
  single value to the page instead of a whole fragment.
- [The JS client]({{ "/the-js-client/" | relative_url }}) covers the
  `island`, `hibiki_island`, and `on` helpers, subscribe params, and the
  transmit route.
- [Broadcast helpers]({{ "/broadcast-helpers/" | relative_url }}) covers
  replace, morph, and page refresh.
- [Channel lifecycle]({{ "/channel-lifecycle/" | relative_url }}) explains
  the graph thread and what happens when code reloads in development.
- [Phlex support]({{ "/phlex-support/" | relative_url }}) makes a Phlex
  component itself reactive.
