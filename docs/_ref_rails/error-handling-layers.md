---
title: Error handling layers
nav_order: 8
---

# Error handling layers

Errors in a reactive channel can come from two places — an action body, or an effect re-running later because of what the action wrote. Three layers catch them, from most specific to last-resort. All three run on the graph thread, since that's where actions and effects run.

## 1. `rescue_from` on the channel

Plain ActionCable error handling, and the right place for expected, per-action failures — validation errors, missing records:

```ruby
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  rescue_from ActiveRecord::RecordNotFound do |e|
    transmit({ error: "not found" })
  end
end
```

The handlers apply exactly as in a stock channel; the only difference is that they run on the graph thread, because that's where the action body runs. Whatever a handler doesn't catch falls through to layer 3.

## 2. `Hibiki.error_handler` — effect errors

When an action's write invalidates effects, those effects re-run *after* the action body — so an error raised inside an effect isn't in the action's stack and `rescue_from` alone may not be where you want to reason about it. The core gem provides an app-level hook for exactly this:

```ruby
# e.g. in an initializer
Hibiki.error_handler = ->(error, effect) do
  Rails.error.report(error, context: { effect: effect.inspect })
end
```

When set, effect errors raised during a flush are routed here instead of propagating. `hibiki_rails` deliberately does not set this for you — it's app policy. Unset, effect errors propagate out of the flush and land in layer 3.

## 3. The graph worker's per-job rescue

The safety net. Every job the graph's worker thread runs — graph build, action, flush — runs inside `Rails.application.executor` (so `CurrentAttributes` are reset between jobs, autoloads are safe off the main thread, and each job gets its own query cache) and is wrapped in a per-job rescue, so one bad action can't take the whole graph down. Anything the first two layers didn't handle is reported to Rails' error reporter:

```ruby
Rails.error.report(error, handled: true, source: "hibiki_rails")
```

Subscribe your error service to the reporter (most already are) and filter on `source: "hibiki_rails"` if you want these separated.

**In development and test it also logs.** `ActiveSupport::ErrorReporter` has no subscribers by default, so in a stock app the report alone went nowhere: no line, no stack, and the only symptom was a fragment that quietly stopped updating. Since 0.3.0 the default reporter writes to `Rails.logger` as well when `Rails.env.local?` —

```
[hibiki_rails] NoMethodError: undefined method 'to_i' for an instance of Hash
/path/to/app/channels/books_channel.rb:127:in 'BooksChannel#load_more'
...
```

— and stays quiet in production, where a real subscriber is doing the job. You need no initializer for this.

To change the behavior for one channel, override `build_graph_actor` and pass your own handler:

```ruby
def build_graph_actor
  Hibiki::Rails::GraphActor.new(on_error: ->(e) { MyErrorService.notify(e) })
end
```
