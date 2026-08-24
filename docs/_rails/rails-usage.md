---
title: Rails usage
nav_order: 5
---

# Rails usage

Most of your reactive logic lives in *channels*. Include `Hibiki::Rails::Channel`, build the graph in `build_graph`, and write actions as plain methods:

```ruby
class CounterChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  # Runs once on the graph's own thread, inside Hibiki.root.
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

  # Actions are plain methods that touch signals directly: each one runs
  # on the graph thread inside one Hibiki.batch, so N writes still mean
  # one re-run per affected effect.
  def increment = @count.value += @step.value
  def burst     = 10.times { @count.value += 1 } # Updates exactly once
end
```

The page supplies a per-page-load graph id (`cid`) and listens on the matching stream:

```erb
<div data-controller="counter" data-counter-cid-value="<%= @cid %>">
  <%= turbo_stream_from "counter", @cid %>
  <%# placeholder — see the initial-state pattern below %>
  <%= render "count", count: 0, doubled: 0 %>
  ...
</div>
```

The controller action sets `@cid = SecureRandom.uuid`. The channel broadcasts to `[channel_name, cid]`; override `stream_name`, `cid`, or both to derive identity differently.

## The initial-state pattern (Turbo transport)

Pages on the Turbo-broadcast transport, like the example above, have an ordering problem the transmit transport doesn't: the graph's effects do their first run inside `subscribed` — usually before the page's `turbo_stream_from` subscription has confirmed — so the first broadcast would be lost. Fix the ordering on the client with the packaged `streamConnected` helper: wait for Turbo to stamp the `connected` attribute on the stream source, then subscribe the graph channel.

The supplied JS client already does all of this for you.
{: .note }

```js
// in the Stimulus controller driving the channel
import { streamConnected } from "hibiki-rails"

async connect() {
  this.consumer = createConsumer()
  await streamConnected(this.element.querySelector("turbo-cable-stream-source"))
  this.subscription = this.consumer.subscriptions.create(
    { channel: "CounterChannel", cid: this.cidValue }, {}
  )
}
```

With that in place, the server-rendered initial HTML only fills the space until the first broadcast arrives — the broadcast always lands and replaces it, so it doesn't have to match the graph's initial state. (The generated `stimulus` and `island` shapes already do all of this.)
