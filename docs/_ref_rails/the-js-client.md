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
that, plus the `Helpers` include described below, the `ApplicationCable`
boilerplate, and the `@rails/actioncable` pin — we added these for you because a stock Rails app has
neither of the last two until a first `rails g channel` was run. 

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
module the engine vendors, pulls in `@rails/actioncable`, and is released
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

Three helpers cover the surface:

- `hibiki_island(channel, cid:, params:)` — the island root: one
  subscription to `channel`, identified by the page's `cid` — a
  per-page-load id (typically a UUID the controller action generated), so
  two tabs on the same page each get their own graph. See
  [Subscribe params](#subscribe-params) for `params:`.
- `on(action, event:, with:, debounce:, confirm:, reset:, fallback:)` —
  forward a DOM event as a channel action. See
  [Events and modifiers](#events-and-modifiers).
- `reactive(name, placeholder)` / `reactive_attrs(name)` — placeholder for
  a single reactive value, paired with the channel's `transmit_value` (see
  [Reactive values]({{ "/reactive-values/" | relative_url }})).

## Events and modifiers

`on` sets one `event->action` token per event on the control. The left
side of that arrow always names an event — a DOM event like `:click` (the
default), `:change`, `:input`, or `:submit`, or the `:visible`
pseudo-event described below. Everything else about the gesture — how long
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

`visible` fires when the control scrolls into view, backed by an
`IntersectionObserver` that is always present in the client. It fires
**once per observation** and re-attaches to the replacement element after
each fragment swap, which is what lets a load-more control double as an
infinite-scroll sentinel and keep paging when one page didn't fill the
viewport. Because an observer can fire again before a swap lands, pair it
with a generation token in `with:` and make the action a no-op when the
token is stale.

The shape of this helper interface is inspired by
[phlex-reactive](https://phlex-reactive.zoolutions.llc)'s `on(...)`
actions.

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

## The transmit transport

Everything so far has covered the upward direction: user gestures becoming
channel actions. The downward direction — re-rendered HTML reaching the
island — travels the same subscription, just the other way, by
[*transmit*](https://api.rubyonrails.org/v8.0/classes/ActionCable/Channel/Base.html#method-i-transmit):
the ActionCable method for sending a message down one subscription,
private to that subscriber.

hibiki_rails can also deliver HTML a second way — the Turbo way,
broadcasting Turbo Streams to a named stream for Turbo's own JS to apply
(see [Broadcast helpers]({{ "/broadcast-helpers/" | relative_url }})). The
packaged client needs none of it: no broadcast stream, no Turbo JS, just
the subscription channel the island already holds.

The recipe is simple: in `build_graph`, wrap the
rendering in an effect and hand the result to `transmit({ html: })`; the contract is the `{ html: }` shape, which the packaged
client knows to swap in. The effect's first run reads your signals, which
subscribes it; every later change re-renders and re-sends. When a `{ html: }` message arrives, the
client replaces each element on the page whose DOM id matches a top-level
element of the fragment — so the fragment's root must carry a stable id.
With ERB, render the partial yourself inside a plain effect:

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

You might expect a race here — an effect transmitting before the page is
ready to receive — but there is none: the client starts listening at
subscribe time, before the server ever runs `build_graph`, so the effects'
first transmits always land, and the server-rendered initial HTML only
fills the space until the first one arrives.

One rule carries over from any reactive UI design: never transmit a fragment containing the input the user is currently typing in.
{: .tip }

For gestures that can't be declared in markup — a drag library's drop
callback, a canvas widget, a keyboard shortcut — `perform`/`performOn`
fire an action through the island's own subscription from your own code:
see [Driving an island from JS]({{ "/driving-an-island/" | relative_url }}).
