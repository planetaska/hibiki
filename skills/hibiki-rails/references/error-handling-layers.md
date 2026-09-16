# Error handling layers

An action runs in two steps, the body you wrote and then the effects that
re-run because of what it changed, and each can raise. Three layers catch
them, all on the graph thread.

| Layer | Catches | Where to set it |
| --- | --- | --- |
| 1. `rescue_from` | errors raised by the action body; never effect errors | on the channel, as in any ActionCable channel |
| 2. `Hibiki.error_handler` | errors raised by effects re-running at flush; the other pending effects still run | `config/initializers/hibiki.rb`; the core gem's hook, unset by hibiki_rails |
| 3. GraphActor safety net | everything else, per job; the thread survives and the ack still goes out | default `Hibiki::Rails.default_error_reporter`; replace via `build_graph_actor` |

```ruby
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  rescue_from ActiveRecord::RecordNotFound do |e|
    transmit({ error: "not found" })
  end
end
```

```ruby
# config/initializers/hibiki.rb
Hibiki.error_handler = ->(error, effect) do
  Rails.error.report(error, context: { effect: effect.inspect })
end
```

Layer 3 reports with `Rails.error.report(error, handled: true, source:
"hibiki_rails")`, so error services that subscribe to the reporter see it;
filter on the source to keep them apart. In development and test it also
logs, because a fresh app has no reporter subscriber and a report alone would
vanish:

```
[hibiki_rails] NoMethodError: undefined method 'to_i' for an instance of Hash
/path/to/app/channels/books_channel.rb:127:in 'BooksChannel#load_more'
```

Per-channel replacement (your callable replaces the default entirely, log
line included):

```ruby
def build_graph_actor
  Hibiki::Rails::GraphActor.new(on_error: ->(e) { MyErrorService.notify(e) })
end
```

Gotchas:

- An effect's first run, during `build_graph`, is not a re-run, so layer 2
  never sees it; it lands in layer 3 and that fragment never gets its first
  render. A blank where a fragment should be means: read the log.
- With no `Hibiki.error_handler`, an effect error is raised after the other
  pending effects ran, and layer 3 catches it.
- Browser-side JavaScript errors are a separate subject; check the Console.

Full docs: https://planetaska.github.io/hibiki/error-handling-layers/
