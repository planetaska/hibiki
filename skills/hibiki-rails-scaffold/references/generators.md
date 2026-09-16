# Generators: the three component shapes (digest)

Each shape scaffolds one working mini-example (one state, one derived, one
action, one effect) to reshape in place. For a whole resource use
`hibiki:rails:scaffold` instead (`references/crud-scaffolding.md`).

| Shape | Command | Writes | Needs install? |
| --- | --- | --- | --- |
| `stimulus` | `bin/rails g hibiki:rails:stimulus NAME [VIEW_PATH]` | `app/channels/<name>_channel.rb`, `app/javascript/controllers/<name>_controller.js` (a `ChannelController` subclass), `app/views/<view_path>/_<name>.html.erb` and `_<name>_display.html.erb` | No |
| `island` | `bin/rails g hibiki:rails:island NAME [VIEW_PATH]` | The channel and the same two partials; no per-component JS | Yes (`hint` when missing) |
| `phlex` | `bin/rails g hibiki:rails:phlex NAME` | The channel, `app/components/<name>.rb` (`Components::Name`), `app/components/<name>_island.rb` | Yes, plus the hibiki_phlex gem (`warn` when missing) |

`VIEW_PATH` is the directory under `app/views`; it defaults to `NAME`.
Namespaced names (`admin/counter`) nest channel, view path and component; the
`stimulus` shape then pins `static channel = "Admin::CounterChannel"` because
the identifier cannot infer it. On jsbundling apps `stimulus` appends the
import/register pair to `controllers/index.js`; importmap apps eager-load it.

## Transport per shape

`stimulus` and `island` broadcast over Turbo Streams: the partial carries
`turbo_stream_from "counter", cid` and the channel's effect calls
`broadcast_replace target: "counter_display", partial: ..., locals: ...`.
`phlex` transmits over the channel's own subscription with no stream line:

```ruby
def build_graph
  @component = Components::Counter.new
  Hibiki::Phlex.render_effect(@component) { |html| transmit({ html: }) }
end

def increment = @component.increment   # public methods are actions
```

The `island` partial shape, which the scaffold's index reuses at larger scale:

```erb
<% cid = local_assigns.fetch(:cid) { SecureRandom.uuid } %>
<%= tag.div(**hibiki_island(CounterChannel, cid:)) do %>
  <%= turbo_stream_from "counter", cid %>
  <%= render "counter/counter_display", count: 0, doubled: 0 %>
  <p><%= tag.button("+1", **on(:increment)) %></p>
<% end %>
```

## Rendering

```erb
<%= render "counter/counter" %>                <%# stimulus and island: view path + name %>
<%= render Components::CounterIsland.new %>    <%# phlex: by class, no view path %>
```

The phlex shape is the hibiki_phlex idiom (component owns state, render effect
re-renders it); it is not the scaffold's `--phlex` flag, whose components are
stateless. Component internals live in the `hibiki-phlex` skill.

See also: https://planetaska.github.io/hibiki/phlex-support/
Full docs: https://planetaska.github.io/hibiki/generators/
