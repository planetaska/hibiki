# Reactive values

A reactive value sends one piece of text, not a fragment: a count in a
heading, an error under a field. Two halves joined by a name that is the same
on both sides and unique across the page; a typo fails silently.

```ruby
# controller: the page's starting value is its job, like any other page data
def index
  @remaining = Todo.where(done: false).count
end
```

```erb
<h1>todos (<%= reactive :remaining, @remaining %> left)</h1>
```

```ruby
def build_graph
  @list = TodoList.new
  transmit_value(:remaining) { @list.remaining }
end
```

| Half | API | Notes |
| --- | --- | --- |
| placeholder (ERB) | `reactive(name, placeholder = "", tag_name: :span)` | emits `<span data-hibiki-value="remaining">3</span>`; the placeholder shows until the first value lands |
| placeholder (Phlex) | `span(**reactive_attrs(:remaining)) { @remaining.to_s }` | same attribute on an element of your own |
| channel | `transmit_value(name) { ... }` in `build_graph` | wraps the block in an effect; each run sends `to_s` of the result as `{ value: { name:, text: } }` |
| address bar | `transmit_url { ... }` in `build_graph` | sends `{ url: }`; the client calls `history.replaceState` |

Rules:

- Pass the real starting value as the placeholder, computed in the controller
  and handed to the view (or to the Phlex component as an argument). The first
  value lands a moment after the page appears, so a literal `0` over a
  database-backed list shows a wrong number and then jumps. `0` is right only
  when the graph starts empty. Keep the query out of the template.
- The block tracks whatever signals it reads; the name is the only thing you
  declare.
- Equality-gated on the emitted string: a run whose text equals the last text
  sent sends nothing, so an action that leaves the count alone costs nothing.
- Names match like a CSS class, document-wide: one value may appear many
  times, inside or outside the island, and every copy updates while keeping
  its own tag, classes, and attributes.
- Text only: the client assigns `textContent`, so markup is never
  interpreted. Send a fragment when the thing that changes is markup.
- Several values that always change together are cheaper as one fragment.
- A placeholder inside a fragment a broadcast replaces must render its
  current value, because the swap resets the text and the gate will not
  re-send an unchanged value. Placeholders outside replaced fragments are
  unaffected.
- Values travel by transmit, so they need no `turbo_stream_from` and mix
  freely with broadcast fragments on the same channel.
- A `ChannelController` subclass overriding `received` must call `super` or
  handle `value` itself, or values stop updating.

`transmit_url`:

```ruby
transmit_url do
  if (id = @editing_id.value) && @rows.value.any? { it.id == id }
    urls.edit_song_path(id)
  else
    urls.songs_path(**query_url_params)   # canonical params, defaults omitted
  end
end

def urls = ::Rails.application.routes.url_helpers
```

Compute a same-origin path (anything else is refused silently), omit params
at their defaults so the first update adds no noise, and render the initial
page from the same params so a reload lands on the state the URL names.
`replaceState`, never `pushState`: the URL mirrors state, so Back leaves the
page normally and there is no history event to handle.

Full docs: https://planetaska.github.io/hibiki/reactive-values/
