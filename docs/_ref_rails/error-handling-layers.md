---
title: Error handling layers
nav_order: 12
---

# Error handling layers

This page explains where an error goes when it is raised inside a
hibiki_rails channel, and where to put the code that handles it. Read it
when a fragment has stopped updating with nothing in the log, or before
you wire the channel into your error service.

A quick orientation for newcomers. In a hibiki_rails app, *signals* are
values the server holds for one page, and *effects* are blocks that
re-run whenever a signal they read changes; together they form the
page's *graph* ([Getting started]({{ "/getting-started/" | relative_url }})
introduces both). An *action* is a public method on your channel that
the browser calls by name. A typical action writes a signal, and the
effects that read that signal re-run after the action body finishes,
sending fresh HTML to the browser.

## Where errors come from

An action runs in two steps: first the action body you wrote, then the
effects that re-run because of what it changed. Each step can raise:

- **The action body itself.** A record is missing, a validation fails,
  a parameter has the wrong shape. This error is raised on the action's
  own call stack, inside the method you wrote.
- **An effect re-running afterward.** The action succeeded and wrote a
  signal, and an effect that read it now raises while re-rendering. This
  happens after the action body has returned, so nothing in the action
  method sees it.

Three layers catch these, from the most specific to the last resort.
All three run on the *graph thread*, the one worker thread that owns a
subscription's graph
([Channel lifecycle]({{ "/channel-lifecycle/" | relative_url }})
explains why there is one). Errors in the browser's JavaScript are a
different subject and are not covered here.

## Layer 1: `rescue_from`, for errors in the action

`rescue_from` is ActionCable's own error handling, and it works in a
hibiki channel as in any other. It is the right place for failures you
expect from a particular action, such as a record that no longer exists:

```ruby
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  rescue_from ActiveRecord::RecordNotFound do |e|
    transmit({ error: "not found" })
  end
end
```

The one difference from a stock channel is where the handler runs: on
the graph thread, because that is where the action body runs.

`rescue_from` sees only errors raised by the action body. Effects re-run
after the body has returned, so an error inside one never reaches these
handlers. An action error that no handler matches falls through to
layer 3.

## Layer 2: `Hibiki.error_handler`, for errors in effects

When effects re-run at the end of an action, the core gem runs every
pending effect even if one of them raises, so one broken effect does not
stop the others from updating their fragments. What it does with the
error is up to you. Set a handler once, in an initializer, and every
effect error is passed to it instead of being raised:

```ruby
# config/initializers/hibiki.rb
Hibiki.error_handler = ->(error, effect) do
  Rails.error.report(error, context: { effect: effect.inspect })
end
```

The handler receives the error and the effect that raised it. This hook
belongs to the core gem, not to hibiki_rails, so it also covers effects
outside any channel. hibiki_rails deliberately leaves it unset, because
what to do with an effect error is a decision for your app. With no
handler, the error is raised once the other pending effects have run,
and layer 3 catches it.

Effects also run once when they are created, during `build_graph`. An
error on that first run is not an effect re-run, so this handler does
not see it. It goes to layer 3, and the effect never sends its first
render, which is why a page that shows nothing where a fragment should
be is worth checking in the log.

## Layer 3: the graph thread's safety net

Every job on the graph thread, whether building the graph, running an
action, or re-running effects, runs inside a rescue. Whatever the first
two layers did not handle lands here, and the job ends. The graph thread
itself survives, so one bad action cannot take the whole subscription
down. The browser is still told the action finished, so a busy
indicator waiting on it clears rather than spinning forever.

The default handler reports the error to Rails' error reporter:

```ruby
Rails.error.report(error, handled: true, source: "hibiki_rails")
```

Most error services subscribe to this reporter already, so these errors
reach the same place as your controllers' errors with no extra setup.
Filter on the source `"hibiki_rails"` if you want them kept apart.

## What you see in development

The Rails error reporter has no subscribers in a fresh app. Before
hibiki_rails 0.3.0, a report in development went nowhere: no log line,
no stack trace, and the only symptom was a fragment that quietly stopped
updating. Since 0.3.0 the default handler also writes to the Rails log
in development and test:

```
[hibiki_rails] NoMethodError: undefined method 'to_i' for an instance of Hash
/path/to/app/channels/books_channel.rb:127:in 'BooksChannel#load_more'
...
```

In production the log line is skipped, because a real subscriber is
doing that job and would otherwise see every error twice. You need no
configuration for any of this.

## Changing the safety net for one channel

The safety net is a callable passed to the channel's `GraphActor`, the
object that runs the graph thread. To replace it for one channel,
override `build_graph_actor` and pass your own:

```ruby
def build_graph_actor
  Hibiki::Rails::GraphActor.new(on_error: ->(e) { MyErrorService.notify(e) })
end
```

Your callable replaces the default entirely, including the development
log line, so log the error yourself if you still want it.
