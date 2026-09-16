# Rails usage: a channel by hand

## The channel

```ruby
# app/channels/counter_channel.rb
class CounterChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @count = Hibiki::State.new(0)
    @step  = Hibiki::State.new(1)
    doubled = Hibiki::Derived.new { @count.value * 2 }   # local: only the effect reads it

    Hibiki::Effect.new do
      broadcast_replace target: "count", partial: "counter/count",
                        locals: { count: @count.value, doubled: doubled.value }
    end
  end

  def increment = @count.value += @step.value      # ten writes in one action: one re-render
  def set_step(data) = @step.value = Integer(data["step"])
end
```

| Rule | Why |
| --- | --- |
| `build_graph` runs once, at subscribe, on the graph thread inside `Hibiki.root` | the root owns every signal and effect, so unsubscribe disposes all at once |
| Signals live in ivars; a derived only an effect reads can stay local | actions need to reach what they write |
| Each effect is a render effect; its first run subscribes it to what it reads | a change to `@count` re-runs only the effects that read it |
| Every public method is an action; the include hides `build_graph`, `subscribed`, `unsubscribed` | anything else public is client-callable |
| An action writes signals and nothing else; the whole body is one `Hibiki.batch` | effects run once after the action returns |
| A one-parameter action receives a string-keyed hash; actions run on the graph thread, one at a time | which keys arrive depends on the view; `current_user` from the connection works, `Current.*` is gone by the next action |

## The view, three ways

Stimulus shape (`hibiki:rails:stimulus`):

```erb
<% cid = local_assigns.fetch(:cid) { SecureRandom.uuid } %>
<div data-controller="counter" data-counter-cid-value="<%= cid %>">
  <%= turbo_stream_from "counter", cid %>
  <%= render "counter/count", count: 0, doubled: 0 %>   <%# placeholder %>
  <button data-action="counter#increment">+1</button>
  <input type="number" name="step" value="1" data-action="change->counter#setStep">
</div>
```

```erb
<%# app/views/counter/_count.html.erb %>
<%# locals: (count:, doubled:) -%>
<p id="count">count: <%= count %> · doubled: <%= doubled %></p>
```

`counter_controller.js` is `export default class extends ChannelController`
(imported from `"hibiki-rails"`) with one method,
`setStep(event) { this.perform("set_step", { step: event.target.value }) }`.
The base infers `CounterChannel` from the identifier (`static channel = "..."`
otherwise), sends the cid, and forwards plain `counter#increment` tokens with
no payload, so declare a method only when it needs one. The fragment's root
`id="count"` and the effect's `target:` are the only link; a typo fails silently.

Island shape (`hibiki:rails:island`), no controller of your own: the same
markup with `tag.div(**hibiki_island(CounterChannel, cid:))` as the root and
`tag.button("+1", **on(:increment))`,
`tag.input(name: "step", **on(:set_step, event: :change))` as controls. A
changed control sends its value under its `name`, so `set_step` still gets
`data["step"]`. The `island CounterChannel do ... end` helper (0.12.0+)
generates the cid, stamps the root, writes the stream line from the channel
class, and yields the cid.

The page-load id `cid` gives each tab its own graph; a subscription without
one is rejected. The channel broadcasts to `[channel_name, cid]`
(`["counter", cid]`), which is what `turbo_stream_from "counter", cid` listens
on. Override `stream_name` or `cid` on the channel when either comes from
elsewhere.

## Two routes for the HTML

| Channel renders with | `turbo_stream_from` inside the island |
| --- | --- |
| `broadcast_replace`, `broadcast_morph`, `broadcast_refresh` | yes |
| `transmit({ html: ApplicationController.render(partial:, locals:) })` / `transmit_value` | no (`island ..., transport: :transmit`) |

Transmit swaps each element whose id matches a fragment root; one channel may
use both routes. Broadcasts give you Turbo's stream actions (morph, refresh);
transmit has fewer moving parts and is what the Phlex render effect uses.

## Placeholders and the first update

Server-rendered partials are placeholders; the graph's first effect run
replaces them right after subscribe, so they need not match the initial state.
On the broadcast route, `turbo_stream_from` opens its own subscription and a
broadcast lands only after it confirms. The packaged `ChannelController` waits
before subscribing; a client written from scratch must:

```js
import { streamConnected } from "hibiki-rails"
await streamConnected(element.querySelector("turbo-cable-stream-source"))
consumer.subscriptions.create({ channel: "CounterChannel", cid }, {})
```

Transmit has no such trap: the client listens from the moment it subscribes.

Rendering without a request: a channel-rendered partial has no controller,
so `params` and `session` are empty, `action_name` is nil, controller ivars
do not exist, and nothing raises. Pass everything through `locals:` under a
strict-locals header so a forgotten local raises at render time.

Full docs: https://planetaska.github.io/hibiki/rails-usage/
