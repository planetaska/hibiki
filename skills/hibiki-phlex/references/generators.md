# Generators: the Phlex shape

```sh
# needs hibiki_phlex (and phlex-rails to render from views); island/phlex
# shapes also need the one-time bin/rails g hibiki:rails:install
bin/rails g hibiki:rails:phlex NAME
```

The component owns the state, the channel owns the transport: one render
effect re-renders the same instance and transmits its HTML down the channel's
subscription. No Turbo streams, no view path (components render by class).

| File | Constant | Role |
|---|---|---|
| `app/channels/counter_channel.rb` | `CounterChannel` | `include Hibiki::Rails::Channel`; `build_graph` creates `Components::Counter.new` and wraps it in `Hibiki::Phlex.render_effect`, transmitting `{ html: }`; public `increment` delegates to the component |
| `app/components/counter.rb` | `Components::Counter` | `Hibiki::Reactive` + `Rerenderable` + `Hibiki::Rails::Helpers`; `state :count, 0`, `derived(:doubled)`; root `div(id: "counter")`; `button(**on(:increment))` |
| `app/components/counter_island.rb` | `Components::CounterIsland` | `div(**hibiki_island(CounterChannel, cid: SecureRandom.uuid))` around a placeholder `render Components::Counter.new` |

Render from any page:

```erb
<%= render Components::CounterIsland.new %>
```

Rules the output encodes:

- The root id is the swap key for transmitted fragments, so keep it
  page-unique (namespaced `admin/counter` yields id `admin_counter`).
- Controls sit inside the re-rendered component; the island's event
  delegation keeps them working across replacements.
- Missing `hibiki_phlex` is a warning, not a failure, so the generator can run
  before the Gemfile edit; a missing `hibiki:rails:install` prints a hint.
- Namespaced names nest the channel and both components the way Rails would.

Full docs: https://planetaska.github.io/hibiki/generators/
