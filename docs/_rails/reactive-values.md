---
title: Reactive values
nav_order: 6
---

# Reactive values

The effects in [Rails usage]({{ "/rails-usage/" | relative_url }}) each
render a *fragment*: a partial or component whose whole HTML travels to
the browser and replaces an element there. Often the thing that changes is
smaller than that. A count in a heading, a running total in a footer, an
error message under a field: one number or one line of text, sitting in
the middle of markup that never changes. A *reactive value* sends just
that text. The view marks the spot with a named placeholder, and the
channel keeps the text in it current.

Here is a todo list whose heading shows how many items remain:

```erb
<h1>todos (<%= reactive :remaining, 0 %> left)</h1>
```

```ruby
def build_graph
  @list = TodoList.new
  transmit_value(:remaining) { @list.remaining }
end
```

Ticking a todo off changes the number in the heading and nothing else. No
partial for the heading exists, and nothing is re-rendered.

## The two halves of a value

A reactive value is a pair: a placeholder in the view and a block in the
channel. A name joins them, so the name must be the same on both sides and
unique across the page. A typo fails silently, because the text arrives
and finds no placeholder to land in.

### The placeholder

The `reactive` helper renders the placeholder:

```ruby
reactive(name, placeholder = "", tag_name: :span)
```

It emits one element that carries the name in a data attribute, with the
placeholder text inside:

```html
<span data-hibiki-value="remaining">0</span>
```

The placeholder text is what the page shows until the first value
arrives, which happens within a moment of the page appearing. Pass
`tag_name:` to get an element other than a `span`. In a Phlex component,
add the attribute to an element of your own with `reactive_attrs`:

```ruby
span(**reactive_attrs(:remaining)) { "0" }
```

### The channel block

`transmit_value` is the channel's half. Call it inside `build_graph`, with
a block that computes the text:

```ruby
transmit_value(:remaining) { @list.remaining }
```

The block is wrapped in an effect, so it follows the same rule as every
effect in Hibiki: it runs once, remembers which signals it read, and runs
again whenever one of them changes. Each run converts the result to a
string and sends it down the channel, and the browser writes it into every
placeholder with that name. The block may read a state, a derived, or an
expression over several signals. The name is the only thing you declare.
What the block depends on, its reads decide.

A run whose text matches the last text sent sends nothing. An action that
changes other signals but leaves the count as it was costs no message.

## One value, many places

A name is like a CSS class rather than a DOM id: the browser matches it
everywhere in the document, so a value may appear any number of times, and
every copy updates. The copies need not sit inside the island. A badge in
the navigation bar can show the same count as the heading:

```erb
<nav>... <%= reactive :remaining, 0, tag_name: :strong %> ...</nav>
...
<h1>todos (<%= reactive :remaining, 0 %> left)</h1>
```

Only the text inside a placeholder changes. Each placeholder keeps its own
tag, classes, and attributes through every update, so two copies of one
value can be styled differently.

## Values are text, not markup

A reactive value is text and only text. The browser assigns it as the
element's text content, so an angle bracket in the value shows up as an
angle bracket. Nothing is ever interpreted as HTML. When the thing that
changes is markup, send a fragment.

Two related limits follow from the shape:

- **Several values that always change together** are better off as one
  fragment. A partial with three numbers in it costs one message. Three
  reactive values cost three.
- **A placeholder inside a fragment that a broadcast replaces** must render
  its current value, not a static default. The replacement resets the
  placeholder's text, and since the value has not changed, the channel
  does not send it again. Placeholders outside any replaced fragment, such
  as the navigation badge, are never affected.

## How the value travels

The channel sends every value over its own subscription, the *transmit*
route described in [Rails usage]({{ "/rails-usage/#two-routes-for-the-html" | relative_url }}).
Both packaged controllers handle it, so reactive values work the same
whether the island runs the generic controller or a `ChannelController`
subclass of your own. They also mix with the broadcast route: one channel
can send a fragment as a Turbo broadcast and a value over transmit at the
same time.

Values are cheap. They ride the island's existing subscription, so a new
value adds one effect on the server and one small message per change, and
no JavaScript object in the browser.

One rule for subclasses. A `ChannelController` subclass that overrides
`received` must call `super`, or handle the `value` message itself, or its
reactive values stop updating.

## Mirroring the address bar with `transmit_url`

The address bar can be treated as one more place on the page that shows
the graph's state. `transmit_url` does for the URL what `transmit_value`
does for a placeholder. A channel calls it once, in `build_graph`, with a
block that computes the URL from the signals:

```ruby
def build_graph
  # ... signals, deriveds, effects ...

  transmit_url do
    if (id = @editing_id.value) && @rows.value.any? { it.id == id }
      urls.edit_song_path(id)
    else
      urls.songs_path(**query_url_params)   # canonical params, defaults omitted
    end
  end
end

private

def urls = ::Rails.application.routes.url_helpers
```

The block runs as an effect like the value block. Whenever a signal it
reads changes and the URL comes out different, the channel sends the new
URL, and the browser rewrites the address bar to it. Compute a path on the
page's own origin. The browser refuses any other origin, silently. Leave
out query params that hold their defaults, or the first update fills the
bar with noise.

The rewrite uses `history.replaceState` instead of  `pushState`. The URL is a
mirror of the state, not a record of how the state got there, so no
history entry is added. The Back button leaves the page as it normally
would instead of stepping back through every search keystroke, and there
is no history event for you to handle.

The mirror pays off when the URL comes back. A reload, or a link someone
shared, should land on the state the URL names. For that, the Rails
controller must render the initial page from the same params, and the
island must pass them to the channel when it subscribes. The generated
scaffold wires this loop end to end; see
[CRUD scaffolding]({{ "/crud-scaffolding/" | relative_url }}). A form's
URL is worth mirroring too, as the example above does: a reload in the
middle of an edit lands on the ordinary edit page for that record.
