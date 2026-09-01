---
title: Phlex support
nav_order: 7
---

# Phlex support

[Phlex](https://www.phlex.fun) builds HTML from plain Ruby classes. A
component is a class with a `view_template` method, and calling the
component returns its HTML as a string. The sister gem `hibiki_phlex`
makes such a component *reactive*: the component holds its own state,
and whenever that state changes it renders itself again and hands you the
new HTML.

Two pieces do the work:

- **Signals in the component.** `Hibiki::Reactive`, from the core gem,
  lets a class declare *signals*: values that remember who read them. The
  component declares its signals with `state` and `derived` and reads them
  as ordinary methods inside `view_template`.
- **A render effect around the component.** An *effect* is a block that
  runs once, notes which signals it read, and runs again whenever one of
  them changes. `hibiki_phlex` wraps the component's render in one, so a
  change to any signal the template read renders the component again.

The gem decides nothing about where the HTML goes. It depends on `hibiki`
and `phlex` only. The block you give the render effect receives each
render's HTML and does with it what it likes: send it to a browser, write
it to a file, compare it in a test. In a Rails app, a channel from
`hibiki_rails` is that block's usual home, and
[In a Rails channel](#in-a-rails-channel) shows the whole loop.

## Installation

```ruby
# Gemfile
gem "hibiki_phlex"
```

The gem needs Ruby 3.4 or later and Phlex 2.4. The pin is strict,
`>= 2.4, < 2.5`, for a reason explained
[at the end of this page](#why-the-phlex-version-is-pinned). To render
components from Rails views you also need `phlex-rails`, which
`hibiki_phlex` does not pull in.

## A reactive component

Here is a todo list. It keeps its items in a signal, computes how many are
left, and renders both:

```ruby
class TodoList < Phlex::HTML
  include Hibiki::Reactive
  include Hibiki::Phlex::Rerenderable

  state(:items) { [] }
  derived(:remaining) { items.count { |item| !item[:done] } }

  def view_template
    div(id: "todos") do
      h2 { "Todos: #{remaining} remaining" }
      ul { items.each { |item| li { item[:title] } } }
    end
  end

  def add(title) = self.items = items + [{ title:, done: false }]
end
```

Line by line:

- **`state(:items) { [] }`** declares a writable signal named `items`.
  Every instance gets its own, and the block gives each one a fresh empty
  array. Calling `items` reads the signal, and `self.items = ...` writes
  it.
- **`derived(:remaining) { ... }`** declares a value computed from other
  signals. It is recomputed when it is read after `items` has changed, and
  not before.
- **The template reads signals as plain method calls.** There is no
  `.value` anywhere, yet each read is tracked. That tracking is what tells
  the render effect which signals the template depends on.
- **`Rerenderable`** lets one instance render more than once, which Phlex
  normally refuses. The render effect requires it, and raises
  `ArgumentError` for a component without it.
- **`add` replaces the array instead of appending to it.** A signal
  notices a write only when the new value differs from the old one by
  `==`, and an array mutated in place is equal to itself. Build a new value
  and assign it. The same rule is why the default is a block: a positional
  default would be one array shared by every instance. See
  [Mutable state defaults]({{ "/mutable-defaults/" | relative_url }}).

The `state` and `derived` macros come from the core gem;
[Class-based reactivity]({{ "/class-based-reactivity/" | relative_url }})
covers them on their own.

## The render effect

`Hibiki::Phlex.render_effect` takes a component and a block, and returns
an effect:

```ruby
list = TodoList.new

effect = Hibiki::Phlex.render_effect(list) do |html|
  puts html
end
# prints the list with 0 remaining

list.add("write docs")
# prints the list again, with 1 remaining

effect.dispose
```

What happens, in order:

1. **The first render runs at once.** `render_effect` renders the
   component before it returns and passes the HTML to the block. During
   that render, every signal the template reads subscribes the effect. So
   the first run is the initial render and the dependency collection in
   one.
2. **A signal write re-renders.** `list.add` writes `items`. The effect
   runs again: the same instance renders, and the block receives the new
   HTML. `remaining` is recomputed along the way, because the template
   reads it.
3. **An equal write does nothing.** Assigning a value equal to the current
   one, by the signal's `==`, neither re-renders nor calls the block.
4. **`dispose` ends it.** An effect created inside `Hibiki.root` or inside
   another effect is disposed along with its owner, which is what happens
   in a channel. A bare caller, like this script, calls `dispose` itself.

The render always happens on the instance you passed in. The signals live
in that instance, so a new `TodoList` per render would start every signal
from its default and remember nothing. That is why the component includes
`Rerenderable`, and why the channel below keeps one instance for as long as
the browser is connected.

One effect covers one component. A change to any signal the template
read re-renders the whole component, and the block receives all of its
HTML. In the ERB style of `hibiki_rails`, each effect renders one partial,
which can be as small as you like. To get smaller updates from Phlex,
split the page into smaller components and give each its own render
effect. A channel may hold several.

## In a Rails channel

With `hibiki_rails`, an ActionCable channel builds the graph when the
browser subscribes and disposes it when the browser leaves.
[Rails usage]({{ "/rails-usage/" | relative_url }}) explains that loop
for ERB partials. With a Phlex component, the channel creates the
component and wraps it in a render effect whose block sends the HTML down
the channel's own subscription:

```ruby
class TodosChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  def build_graph
    @list = TodoList.new
    Hibiki::Phlex.render_effect(@list) { |html| transmit({ html: }) }
  end

  # Public methods are actions the page can call.
  def add(data) = @list.add(data["title"])
end
```

`build_graph` runs once per subscription. The render effect's first run
transmits the initial HTML, and the packaged client replaces the element
on the page whose id matches the fragment's root, here `todos`. Each
action writes a signal, the effect re-runs, and the same element is
replaced again. The effect belongs to the channel's root, so it is
disposed with everything else when the browser unsubscribes.

The page renders the component once as a placeholder, inside an *island*:
an element that subscribes to the channel and whose descendants can call
its actions. A second component wraps the island, so any page can render
it with `render TodoListIsland.new`:

```ruby
class TodoListIsland < Phlex::HTML
  include Hibiki::Rails::Helpers

  def view_template
    div(**hibiki_island(TodosChannel, cid: SecureRandom.uuid)) do
      render TodoList.new

      form(**on(:add, event: :submit)) do
        input(type: "text", name: "title", placeholder: "new todo")
        button { "add" }
      end
    end
  end
end
```

`Hibiki::Rails::Helpers` provides `hibiki_island` and `on`. Each returns a
hash of data attributes, which is why they are splatted into the element.
The placeholder is a throwaway instance. The channel's long-lived instance
takes over from its first transmit, which arrives within a moment of the
page appearing. Elements inside the reactive component can call actions
the same way: include the helpers there too and write
`button(**on(:toggle, with: { index: }))`. The helpers are covered in
[The JS client]({{ "/the-js-client/" | relative_url }}).

The `hibiki:rails:phlex` generator writes all of this for you: the
channel, the component, and an island component that wraps it so any page
can render it in one line. See the
[Phlex shape]({{ "/generators/#phlex-shape" | relative_url }}) in
Generators.

### Transmit or broadcast

The channel above uses the *transmit* route: the HTML rides the channel's
own subscription, and no Turbo stream is involved. The other route is a
Turbo broadcast, with `turbo_stream_from` in the view and a broadcast
helper in the block:

```ruby
Hibiki::Phlex.render_effect(@list) do |html|
  broadcast_replace target: "todos", html:
end
```

Both work with a render effect. Transmit has fewer moving parts and is the
default for Phlex. Broadcasts give you Turbo's stream actions, such as
morphing, and carry an ordering trap around the first update that
transmit does not have.
[Two routes for the HTML]({{ "/rails-usage/#two-routes-for-the-html" | relative_url }})
compares them.

### Deferring re-renders

`render_effect` accepts a `scheduler:` and passes it to the effect. A
scheduler decides when a re-run happens instead of running it at once.
`hibiki_rails` ships one, `Debounce`, which merges a burst of changes into
one render per window:

```ruby
scheduler = Hibiki::Rails::Debounce.new(actor: graph_actor, wait: 0.2)

Hibiki::Phlex.render_effect(@list, scheduler:) { |html| transmit({ html: }) }
```

Within one action, the channel already merges every write into a single
render. A debounce is for the case across actions: many quick actions, or
a burst of database pings, should mean one render rather than one each.
The first render is never deferred.

## Why the Phlex version is pinned

A Phlex component renders once. Calling it a second time raises
`Phlex::DoubleRenderError`. Phlex 2 records that an instance has rendered
in a single private instance variable, `@_state`, and keeps everything
else about a render per call. So `Rerenderable#rerender` clears that
variable and calls the component again. That is the entire adapter.

It leans on a private implementation detail, so the gem guards it two
ways. The gemspec allows only the Phlex minor versions that have been
tested, and a contract spec in the gem exercises the Phlex behavior
directly. Raising the version bound with Phlex's internals moved fails
that spec in CI instead of failing in your app.

## Not the same as the scaffold's `--phlex`

Two different Phlex idioms live in this project. On this page the
*component* owns the state, and a render effect re-renders it. The CRUD
scaffold's `--phlex` flag is the other idiom: there the *channel* owns the
state, so its components are ordinary views that receive their values as
keyword arguments, and `hibiki_phlex` is not involved at all. If that is
what you are after, see
[Phlex instead of ERB]({{ "/crud-notes/#phlex-instead-of-erb" | relative_url }}).
