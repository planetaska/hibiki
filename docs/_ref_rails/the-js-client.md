---
title: The JS client
nav_order: 6
---

# The JS client

Everything reactive in a `hibiki_rails` app runs on the server: the signals,
the effects, and the rendering they drive. The browser has two jobs — send
the user's gestures up, and swap the returned HTML in — and the gem ships
the JavaScript that does both. It is one generic
[Stimulus](https://stimulus.hotwired.dev) controller that drives any
*island*: a region of the page bound to one channel subscription. You
register the controller once, declare islands in your markup, and write no
per-page JavaScript.

## Installation

The gem vendors its own JavaScript, the way turbo-rails does: the engine
puts `hibiki.js` on the app's asset path and merges the `"hibiki-rails"`
pin into the import map, so an importmap-rails app has nothing to download
— only a controller to register. `bin/rails g hibiki:rails:install` does
that, plus the `Helpers` include described below and the `ApplicationCable`
boilerplate — added for you because a stock Rails app has none until a
first `rails g channel` is run. The client rides turbo-rails' Action Cable
consumer, so there is no `@rails/actioncable` pin to add (since 0.11.0; an
older install's pin is harmless). A second pin, `hibiki-rails/motion`,
serves an optional module: with it, an element you mark can finish a CSS
transition before a re-render removes it from the page. The scaffold
imports it, and [Motion explained]({{ "/motion-explained/" | relative_url }}) describes it.

If you do not wish to use the install generator, you can create the one-line shim yourself:

```js
// app/javascript/controllers/hibiki_controller.js
// registers as "hibiki" — the helpers hardcode that identifier
export { default } from "hibiki-rails"
```

The registration is a file-backed shim on purpose. Importmap apps
eager-load it from the controllers directory; jsbundling apps get the
matching import/register pair in `controllers/index.js` (the install
generator appends it); and because it is derived from a real controller
file, `bin/rails stimulus:manifest:update` (for example, everytime you run `bin/rails g stimulus`) regenerates the registration file instead of dropping it.

An app that bundles its JavaScript (jsbundling, vite) installs the client
from npm instead: `npm install hibiki-rails`. The
[npm package](https://www.npmjs.com/package/hibiki-rails) is the same
module the engine vendors, takes `@hotwired/turbo-rails` as a peer, and is released
in lockstep with the gem — one npm version per gem version, pinned to the
same number. [Version lockstep]({{ "/version-lockstep/" | relative_url }})
has the full release table and the upgrade notes.

## Islands and helpers

An island is a DOM subtree the controller keeps live: it opens the channel
subscription when the island appears, forwards the events you declared as
channel actions, and swaps each incoming HTML fragment in by its DOM id.
What makes a subtree an island — and which events it forwards — is declared
entirely in the markup, through `data-hibiki-*` attributes. You never write
those attributes by hand; view helpers generate them. Each helper returns a
hash of attributes, so you splat it (`**`) into a tag builder or a Phlex
element.

The helpers live in `Hibiki::Rails::Helpers`, and the gem never mixes the
module into your views for you — include it yourself wherever the helpers
should be callable. In an ERB app that is `ApplicationHelper`, which makes
them available in every view; in a Phlex app, include it in each component
that needs them:

```ruby
# app/helpers/application_helper.rb
module ApplicationHelper
  include Hibiki::Rails::Helpers
end
```

With the include in place, a view declares an island like this:

```erb
<%= tag.div(**hibiki_island(TodosChannel, cid: @cid)) do %>
  <%= render TodoList.new %>  <%# placeholder; replaced by DOM id %>
  <%= tag.form(**on(:add, event: :submit)) do %>
    <input type="text" name="title">
    <button>add</button>
  <% end %>
<% end %>
```

The outer `div` is the island root: `hibiki_island` sets the attributes
that attach the controller and name the channel to subscribe to. Inside it, `on` marks the form as a control: submitting it sends an
`add` action — carrying the form's fields — up the subscription instead of
making an HTTP request. The rendered `TodoList` is the part the server
will keep re-rendering, matched by its DOM id.

Since 0.12.0, the `island` helper writes the island root for you: it
generates the cid, stamps the `div`, and derives the channel's
`turbo_stream_from` line when the channel broadcasts.
{: .tip }

With the `island` helper, the same view becomes:

```erb
<%= island TodosChannel, transport: :transmit do %>
  <%= render TodoList.new %>
  <%= tag.form(**on(:add, event: :submit)) do %>
    <input type="text" name="title">
    <button>add</button>
  <% end %>
<% end %>
```

`transport: :transmit` says this channel sends its HTML by transmit rather
than by Turbo broadcast, so the root needs no stream source. [Does an
island need a Turbo stream?](#does-an-island-need-a-turbo-stream) explains
the choice.

Six helpers cover the surface:

- `hibiki_island(channel, cid:, params:)` — the island root: one
  subscription to `channel`, identified by the page's `cid` — a
  per-page-load id (typically a UUID the controller action generated), so
  two tabs on the same page each get their own graph. See
  [Subscribe params](#subscribe-params) for `params:`. This is the
  primitive, and the form that Phlex components use.
- `island(channel, cid:, params:, transport:, tag_name:, **attributes) { |cid| }`
  — the same root as an ERB block (it needs ActionView's `capture`, so it
  works only in ERB). Omit `cid:` and the helper generates a UUID; the
  block receives the cid either way. `transport:` names how the channel
  sends its HTML back: `:broadcast`, the default, puts the channel's
  `turbo_stream_from` inside the root; `:transmit` leaves it out. Every other
  keyword lands on the root element (`class:`, `id:`, `tag_name: :section`),
  and a `data:` hash is merged beneath the island's own keys. Pass the
  channel class itself, never a string. For a dynamic name, `constantize`
  it at the call site, and never take it from a request param.
- `on(action, event:, with:, debounce:, confirm:, reset:, fallback:)` —
  forward a DOM event as a channel action. See
  [Events and modifiers](#events-and-modifiers).
- `reactive(name, placeholder)` / `reactive_attrs(name)` — placeholder for
  a single reactive value, paired with the channel's `transmit_value` (see
  [Reactive values]({{ "/reactive-values/" | relative_url }})).
- `props(indeterminate:, scroll_top:, scroll_left:, key:)` — state of an
  element that no HTML attribute can express. See
  [DOM properties](#dom-properties).
- `focus(select:)` — put the cursor in a field that a render opens. See
  [Focus](#focus).

## Events and modifiers

`on` sets one `event->action` token per event on the control. The left
side of that arrow always names an event — a DOM event like `:click` (the
default), `:change`, `:input`, or `:submit`, a key such as
`"keydown.esc"` (see [Keys](#keys)), or the `:visible` pseudo-event
described below. Everything else about the gesture — how long
to wait, whether to ask first, whether to reset — lives in a separate
attribute scoped to the control. That keeps the token list parseable by
whitespace, and lets one element answer several events:

```erb
<%= tag.button(**on(:load_more, event: %i[click visible], with: { shown: rows.size })) %>
```

| option | what it does |
| ------ | ------------ |
| `event:` | one event, or a list of them. |
| `with:` | a hash merged into every payload from this control. |
| `debounce:` | milliseconds to let the gesture settle before performing. `:input` gets **250 ms by default** — pass `debounce: 0` to send every keystroke. The payload is built when the action fires, so the last value wins. |
| `confirm:` | a `window.confirm` message. Declining performs nothing (and does not submit the form). Note that `data-turbo-confirm` does *not* work on a hibiki control — it isn't a Turbo-driven form. |
| `reset:` | `false` keeps a submitted form's inputs. The default resets them, which is right for an "add" form and wrong for an edit one: the reset runs synchronously, before the server has replied, so a failed commit would discard what the user typed. |
| `fallback:` | `true` makes the control's own native behavior its degraded path — see [Falling back to native behavior](#falling-back-to-native-behavior). |

Each action carries a payload. A changed control contributes one entry
under its own `name`: a checkbox sends its **checked state** as a boolean,
a multi-select sends an **array** of its selected values, everything else
sends `value`. A submitted form sends its `FormData`.

A debounced field holds text the server has not heard yet, and a render
can reach the field during that wait: the visitor's own, or one that
another visitor's save caused. Since 0.17.0 the field wins. The client
keeps the typed text and the caret through the render until the debounced
action is sent. After that the server's value wins again, so a Reset or a
failed save can still overwrite the field. An action that is not debounced
first sends the island's pending debounced input, so the server hears
gestures in the order the visitor made them: Enter pressed straight after
the last keystroke saves the whole text.

Only a text field wired with a debounced `:input` is kept this way. A
field that sends nothing until `change` or `submit` is drawn from the
server's value on every render, so a form that must keep its typing sends
each input, as the scaffold's forms do. Checkboxes, radio buttons, file
inputs, and multi-selects are not recorded.

`visible` fires when the control scrolls into view, backed by an
`IntersectionObserver` that is always present in the client. It fires
**once per observation** and re-attaches to the replacement element after
each fragment swap, which is what lets a load-more control double as an
infinite-scroll sentinel and keep paging when one page didn't fill the
viewport. Because an observer can fire again before a swap lands, pair it
with a generation token in `with:` and make the action a no-op when the
token is stale.

Never give a `visible` control a `fallback:`. The fallback runs the
element's native behavior whenever the island is not live, and for a
sentinel that means scrolling into view would navigate. When the control
needs a degraded path, split it as the scaffold does: a wrapper that
carries only `visible`, and a link inside it that carries `click`, a real
href, and `fallback: true`.

The shape of this helper interface is inspired by
[phlex-reactive](https://phlex-reactive.zoolutions.llc)'s `on(...)`
actions.

## Keys

Since 0.17.0, `event:` also takes a key, written `keydown.<key>`. A form
can close on Escape and a page can have hotkeys with no JavaScript of
your own:

```erb
<%= tag.div(**on(:cancel, event: "keydown.esc")) do %>
  <%= tag.form(**on(:save, event: :submit, reset: false)) do %>
    ...
  <% end %>
<% end %>

<%= link_to "New song", new_song_path,
      **on(:new_form, event: ["click", "keydown.n@window"]) %>
```

Pressing the key sends the action with the control's `with:` payload.
`confirm:`, `debounce:`, and the busy mark apply as they do to a click.

A key is heard in one of two scopes:

- **`keydown.<key>`** is heard while focus is inside the element. The
  client walks up from the focused element and takes the nearest element
  that declares the pressed key, so Escape on a wrapper is heard from
  every field within it.
- **`keydown.<key>@window`** is heard anywhere on the page, for as long as
  the element is rendered. The element may be hidden, so a hotkey needs no
  visible button. While the visitor is typing in a text field, a select,
  or an editable element, a window key fires only if it is `esc` or
  carries `ctrl` or `meta`; a plain `n` stays a typed letter.

The key is a letter, a digit, or one of these names: `enter`, `tab`,
`esc`, `space`, the arrow keys `up`, `down`, `left`, and `right`, `home`,
`end`, `page_up`, and `page_down`.

Modifiers go in front, joined by `+`: `keydown.ctrl+s`,
`keydown.meta+shift+k`. They are `ctrl`, `meta`, and `shift`, and they
match exactly: `keydown.s` does not fire on Ctrl+S. For "Command on a Mac,
Control elsewhere", list both tokens:
`event: ["keydown.ctrl+s", "keydown.meta+s"]`. There is no `alt`, because
on macOS the Option key changes the character a key reports.

Four rules are worth knowing before you wire a key:

- **A matched key's default is prevented.** `keydown.ctrl+s` keeps the
  browser's Save dialog closed. A key no control declares is left alone.
- **Some keydowns are ignored.** A key pressed during IME composition and
  the repeats of a held key send nothing.
- **One element takes one action.** `on` returns a single action, however
  many events it lists, so a form wired for `submit` cannot also send
  `cancel` on Escape. Put the key on a wrapper, as in the example above.
- **Invalid tokens raise when the view renders.** An unknown key or
  modifier, `shift` with a digit, and a bare `keydown` each raise an
  `ArgumentError`. For typed text, use `:input`.

A key without a scope needs focus inside its element. The `focus` helper
puts it there when a form opens: see [Focus](#focus).

## Falling back to native behavior

`fallback: true` is for a control that already *has* a native behavior — a
link with a real `href`, a form with a real `action`:

```erb
<%= link_to "Edit", edit_song_path(song.id),
            **on(:edit, with: { id: song.id }, fallback: true) %>
```

Only a **`ready`** island intercepts the gesture and performs the channel
action. In every other state — connecting, offline, stalled — the hibiki
client stands aside entirely: no `preventDefault`, and the browser does
exactly what the markup says.

Note the difference from a control without `fallback:`. There, a gesture
that arrives while the island is still connecting is queued, and the
action is sent once the subscription confirms. A fallback control
deliberately skips that queue: its link or form can answer right now,
while a queued gesture would leave the user looking at an unchanged page
until the socket recovered.

A socket can also be dead without the client knowing it yet. When a
performed action's send reports failure, the client settles the trip and
runs the native behavior by hand — `form.submit()` for a form,
`location.assign` for a link. The gesture never left the page, so it
cannot double-fire.

Two guarantees ride along:

- **`confirm:` gates the native path too.** A destructive submit must not
  slip past its dialog just because the island happens to be down.
- **Native submits get a fresh CSRF token.** Before letting (or making) a
  form submit natively, the client copies the `csrf-token` meta value into
  the form's `authenticity_token` field. This is important: fragments
  refreshed by a channel are rendered without a session, so every updated
  `button_to` form is tokenless — and the first broadcast replaces the
  initial rendered fragment seconds after page load.

The net effect is one set of markup working at three levels: live island,
degraded (scripts ran, socket down), and no scripts at all. Hibiki's generated
scaffold leans on this pattern for its New and Edit links, its destroy
`button_to`, its controls form and its page control —
[CRUD scaffolding]({{ "/crud-scaffolding/" | relative_url }}) shows the
pattern in full.

## DOM properties

Some state of a control has no HTML attribute. A checkbox's
`indeterminate`, the dash a select-all box shows when only some rows are
ticked, exists only as a property of the DOM element. So does a
container's scroll position. A re-rendered fragment is HTML, so it cannot
carry either one. The `props` helper (since 0.16.0) writes the wanted
properties beside the element's other attributes, and the client assigns
them when the island connects and again after every render:

```erb
<%= check_box_tag "all", "1", all_selected,
      **on(:select_all, event: :change)
          .deep_merge(props(indeterminate: some_selected)) %>
```

The channel needs nothing new. It re-renders the fragment as it always
does, with `some_selected` computed from its signals, and the property
follows the markup. Both transports are covered, and so is a page refresh
sent with `broadcast_refresh`.

`on` and `props` each return a hash under the same `data:` key, so
splatting both into one tag keeps only the second. Combine them with
`deep_merge`, as above, or with `mix` in a Phlex component:
`input(type: "checkbox", **mix(on(:select_all, event: :change), props(indeterminate: some)))`.
{: .tip }

`props` accepts three properties:

| property | value | when the client assigns it |
| -------- | ----- | -------------------------- |
| `indeterminate:` | `true` or `false` | after every render. The browser clears the property when the box is clicked, and the next render sets it to what the server says. |
| `scroll_top:`, `scroll_left:` | pixels; `nil` leaves the position alone | when the element is new, and again only when the helper's output changes. The visitor's own scrolling survives every other render. |

A scroll position often has to be applied again though its value stays
the same: "back to the top on each page change" is always `0`. For that,
`props` takes `key:`, any value that converts to JSON. The client ignores
the key itself; a different key makes the output different, and a
different output is assigned again.

```erb
<%= tag.div class: "list", **props(scroll_top: 0, key: page) do %>
```

This pane scrolls to the top whenever `page` changes and keeps its
position through every render in between.

Three limits apply:

- **The element must be inside an island.** The client looks for
  properties only there.
- **The three names are an allowlist.** Any other name raises an
  `ArgumentError` when the view renders, and the client ignores a name it
  does not know, so a fragment can never set `innerHTML` or an event
  handler.
- **`props` assigns properties and calls no methods.** Opening a modal
  dialog and playing media are method calls, and they still need
  JavaScript of your own. Moving focus is a method call too, and it has a
  helper of its own: see [Focus](#focus).

State that has an attribute needs no helper. `value`, `checked`,
`disabled`, and `open` on a `<details>` element ride the fragment like any
other markup.

## Focus

A render can open a form, and a render can close one. Since 0.17.0 the
client moves keyboard focus at both moments, so a visitor can open a row,
type, and press Escape without reaching for the mouse.

### A field that a render opens

The `focus` helper marks the element that should take the cursor when it
appears:

```erb
<%= text_field_tag "title", form.title, **focus(select: true) %>
```

`select: true` also selects the field's text. Like `on` and `props`,
`focus` returns a hash under the `data:` key, so combine them with
`deep_merge`, or with `mix` in a Phlex component:
`**on(:set_field, event: :input).deep_merge(focus)`.

The client focuses a marked element under these rules:

- **Once, on the render that brings it.** Later renders that keep the
  element leave focus alone.
- **Only on a render this tab's own action caused.** Another visitor's
  save never moves the cursor, and neither does a page refresh sent with
  `broadcast_refresh`.
- **Never on page load.** A marked element in the page's first HTML is not
  focused. Use the `autofocus` attribute there.
- **Never away from unsent typing.** A field whose debounced input has yet
  to be sent keeps the focus.

As with `props`, the element must be inside an island.

### A render that removes the focused element

When a form closes, the field that held focus is gone, and the browser
drops focus to the page body. A keyboard user loses their place, and the
island stops hearing keys. The client gives focus back to a control, and
the view needs nothing written for it. It looks for a target in this
order:

1. **The element with the same id.** A field that a render replaced keeps
   its focus and its caret. Under the transmit transport, which replaces
   elements on every render, this covers each field that has an id.
2. **The control that opened the form**, when the form's field carries
   `focus`: the row's Edit link, the New button. The client remembers
   which control's action brought the marked field, and finds it again
   after a re-render by its id, or by its action and `with:` payload.
3. **The first control inside the nearest ancestor that has an id**, when
   that ancestor is still on the page.

Only a control ever takes focus, never a container. When the client finds
none of the three, as after a row is destroyed, it leaves focus where the
browser put it. The rule applies to every render, on both transports and
after a page refresh, and it never moves focus that the visitor has since
put somewhere else.

The scaffold's forms carry no `focus` mark, so closing one returns focus
by the first and third rules only. Add `focus` to the first field of a
generated form to have it take the cursor on opening and return to its
Edit or New control on closing.

## Subscribe params

Back on the island root: `hibiki_island` takes one more option, `params:`,
a hash of extra values the client sends along when it opens the
subscription. On the server they arrive as the channel's subscription
params — read `params[:record_id]` the same way you would read the
built-in `params[:cid]`.

The todos island earlier needed no `params:` because its page is about the
whole collection — `TodosChannel` can load the todos without being told
anything else. A show page is different: its island is about *one* book,
and the channel must learn which one before it builds its signal graph.
The subscription is the only server-side hook that runs that early, so the
id rides along as a subscribe param:

```erb
<%= tag.div(**hibiki_island(BookChannel, cid:, params: { record_id: @book.id })) do %>
```

The `island` helper takes the same option:

```erb
<%= island BookChannel, params: { record_id: @book.id } do %>
```

**Subscribe params are client-supplied and untrusted, exactly like query
params on a request.** Anyone can open a socket and send whatever they like, so a
channel may use one only to **look up a record inside a scope it chooses
itself**, and must `reject` when that lookup fails:

```ruby
private

def record_id = @record_id ||= current_user.books.where(id: params[:record_id]).pick(:id)

def subscribed
  return reject unless record_id   # before super: no graph for an unknown id

  super
  return if subscription_rejected?

  stream_from "book:#{record_id}:changed"   # built from what the lookup returned
end
```

Never interpolate a param into a streamable name, a class name, a column
name, or a scope. The streamable a channel streams from is always derived
server-side from the record it has already loaded and authorized —
otherwise a client naming its own streamable is reading other people's
broadcasts. The client cannot override `channel` or `cid` through
`params:`.

## Does an island need a Turbo stream?

No. The island root gives the client one Action Cable subscription, and
re-rendered HTML can come back down that same subscription: the channel
renders in an effect and calls `transmit({ html: })`, and the client swaps
each fragment in by its root DOM id. `transmit_value` travels the same
way. No Turbo stream is involved, so the island below is complete as it
stands:

```erb
<% cid = SecureRandom.uuid %>
<%= tag.div(**hibiki_island(TodosChannel, cid:)) do %>
  <%= render "todos/list", todos: [] %>
<% end %>
```

Add `turbo_stream_from` inside the island only when the channel renders
with the broadcast helpers. Those publish Turbo Streams to a named
stream — `stream_name`, by default `[channel_name, cid]` — that Turbo's
own JS applies, so the page must listen on it:

```erb
<% cid = SecureRandom.uuid %>
<%= tag.div(**hibiki_island(CounterChannel, cid:)) do %>
  <%= turbo_stream_from channel_name, cid %>
  <%= render "counter/count", count: 0 %>
<% end %>
```

| Channel renders with | `turbo_stream_from` inside the island |
| -------------------- | ------------------------------------- |
| `broadcast_replace`, `broadcast_morph`, `broadcast_refresh` | yes |
| `transmit({ html: })` / `transmit_value` | no |

With the `island` helper, the line is written for you. By default, the root
contains `turbo_stream_from channel.channel_name, cid`, derived from the
channel class, so renaming the channel cannot leave a stale streamable
behind. `transport: :transmit` leaves it out.
{: .tip }

With the `island` helper, the two islands above become:

```erb
<%= island TodosChannel, transport: :transmit do %>
  <%= render "todos/list", todos: [] %>
<% end %>

<%= island CounterChannel do %>
  <%= render "counter/count", count: 0 %>
<% end %>
```

A channel that overrides `stream_name` passes `transport: :transmit` and writes its
own `turbo_stream_from` inside the block, using the cid the block yields:

```erb
<%= island BookChannel, params: { record_id: @book.id }, transport: :transmit do |cid| %>
  <%= turbo_stream_from "book", @book.id, cid %>
  ...
<% end %>
```

The client handles both shapes. If the island root contains its own
`<turbo-cable-stream-source>`, the client waits for that source to report
`connected` before it subscribes, so the graph's first broadcast is not
lost. If there is none, it subscribes right away, and its `received`
handler is registered at subscribe time, so the first transmit always
lands. The two transports differ only on the channel side; in the view
the difference is that one line. [Broadcast helpers]({{
"/broadcast-helpers/" | relative_url }}) covers the channel side of
broadcasting; the next section covers the channel side of transmit.

## The transmit transport

The view side of this transport is the bare island above. On the channel
side, the HTML travels by
[*transmit*](https://api.rubyonrails.org/v8.0/classes/ActionCable/Channel/Base.html#method-i-transmit),
the Action Cable method for sending a message down one subscription,
private to that subscriber — the same subscription the gestures came up.

In `build_graph`, wrap the rendering in an effect and hand the result to
`transmit({ html: })`. The effect's first run reads your signals, which
subscribes it; every later change re-renders and re-sends. When the
`{ html: }` message arrives, the client replaces each element on the page
whose DOM id matches a top-level element of the fragment, so the
fragment's root must carry a stable id. Just before it swaps, the client
dispatches `hibiki:before-render` from the island root, with the swap
itself in `event.detail.render`. A listener may replace that function
with one that waits, the way Turbo's own `turbo:before-stream-render`
allows. The motion module uses this to hold a swap until a leaving
element's transition ends; app code rarely needs it. With ERB, render the
partial yourself inside a plain effect:

```ruby
def build_graph
  @todos = Hibiki::State.new(Todo.order(:created_at).to_a)

  Hibiki::Effect.new do
    transmit({ html: ApplicationController.render(
      partial: "todos/list", locals: { todos: @todos.value }
    ) })
  end
end
```

(A partial rendered from a channel has no request context — no
`params`, no `current_user` helper. [Broadcast helpers]({{
"/broadcast-helpers/" | relative_url }}) covers the implications.)

With Phlex, `Hibiki::Phlex.render_effect` from the hibiki_phlex gem rolls
the effect and the render into one call — re-rendering the *same*
component instance each time, so the signals living in it keep their
state:

```ruby
def build_graph
  @list = TodoList.new
  Hibiki::Phlex.render_effect(@list) { |html| transmit({ html: }) }
end
```

`{ html: }` is one of three message shapes the client understands. The
other two have channel-side helpers of their own: `transmit_value` sends a
single piece of text for the client to write into every matching
`data-hibiki-value` placeholder (see
[Reactive values]({{ "/reactive-values/" | relative_url }})), and
`transmit_url` mirrors graph state into the address bar via
`history.replaceState`.

Because the client is listening before the server runs `build_graph`,
the effects' first transmits always land. The server-rendered HTML only
fills the space until the first one arrives, so it need not match the
graph's initial state.

Avoid transmitting a fragment that contains the input the user is typing
in. A transmit replaces the field with a new element on every render.
Since 0.17.0 the client puts focus, the caret, and unsent text back on a
replaced field that keeps its id, but a field outside the fragment is
never disturbed at all.
{: .tip }

For gestures that can't be declared in markup — a drag library's drop
callback, a canvas widget — `perform`/`performOn`
fire an action through the island's own subscription from your own code:
see [Driving an island from JS]({{ "/driving-an-island/" | relative_url }}).
