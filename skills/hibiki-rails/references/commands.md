# Commands and dialogs

Since 0.20.0. A command changes the page in the browser on an event, with no
round trip. Use one for state only the browser cares about (a menu open, a
class, focus); keep state the server should know in a signal.

Setup: the page imports the module once. `hibiki:rails:install` appends the
line to `app/javascript/application.js`; an app installed before 0.20.0 adds
it by hand or re-runs the generator. Without it a command does nothing and
the console warns once.

```js
import "hibiki-rails/commands"
```

`js` starts a list; `on` takes it where it takes an action name. Commands
chain and run in order, without waiting for the server:

```erb
<%= tag.button "Menu", **on(js.toggle("#menu")) %>
<ul id="menu" hidden>...</ul>

<%= tag.button "Cancel", **on(js.hide("#panel").push(:cancel)) %>
<%= tag.button "Archive", **on(js.hide({ closest: "li" }).push(:archive, with: { id: note.id })) %>
```

| Command | Does |
| --- | --- |
| `show(target)`, `hide(target)`, `toggle(target)` | removes, adds, flips the `hidden` attribute |
| `add_class(names, to:)`, `remove_class(names, to:)`, `toggle_class(names, to:)` | class names, a string or an array |
| `set_attribute(name, value, to:)`, `remove_attribute(name, to:)` | writes or removes an attribute |
| `toggle_attribute(name, value = "", to:)` | sets it when absent, removes it when present |
| `focus(target)`, `focus_first(target)` | focuses the target, or the first link, button or field inside it |
| `dispatch(name, to:, detail:, bubbles: true)` | fires a `CustomEvent` for your own JavaScript |
| `push(action, with:)` | performs a channel action |
| `show_modal(target)`, `close_dialog(target)` | a `<dialog>`'s own methods |

Targets: nothing is the control itself; a CSS selector string is looked up in
the whole document and every match is acted on; `{ inner: selector }` is
every match inside the control; `{ closest: selector }` is its nearest
matching ancestor.

Rules:

- A command's change lasts until the server next renders that element: a
  replace swaps the element, a morph resets its attributes to the server's
  HTML. Use commands on elements the channel does not render.
- `push` behaves as the action form of `on`: busy mark, a submitted form's
  fields, a changed field's value. Its payload goes on `push(..., with:)`;
  `with:` on `on` beside a list raises.
- `confirm:` and `debounce:` on `on` apply to the whole list. `fallback: true`
  needs a `push` in the list. A list takes every event an action does:
  `on(js.hide("#panel"), event: "keydown.esc")`.
- A list prevents the event's default (a link does not navigate).
- One control takes one list or one action, never both: put the action in
  the list with `push`.
- Commands run only on a control inside an island; targets may be anywhere.
- A CSS rule setting `display` can override `hidden`; Tailwind 4's reset
  makes `hidden` win.
- Refused attribute names: any beginning `on`, `style`, `srcdoc`,
  `data-controller`, `data-action`, `data-hibiki-*`.
- A refused attribute, an empty list, or a malformed target raises
  `ArgumentError` when the view renders.
- No timed steps or transitions, and the channel cannot send a command: a
  change the server decides on is a render.

## Dialogs

Use one of the two ways per dialog, chosen by who must know it is open.

The browser owns it (a menu, a help panel):

```erb
<%= tag.button "About", **on(js.show_modal("#about")) %>
<dialog id="about">
  <%= tag.button "Close", **on(js.close_dialog) %>
</dialog>
```

`close_dialog` with no target closes the dialog the control is in.

The server owns it (a form it may refuse to save):

```erb
<%= tag.dialog id: "editor",
      **on(:cancel, event: :cancel).deep_merge(modal(open: form.editing?)) do %>
  <%= tag.form(**on(:save, event: :submit, reset: false)) do %>
    <%= text_field_tag "title", form.title,
          **on(:set_field, event: :input).deep_merge(focus(select: true)) %>
    <button>Save</button>
    <%= tag.button "Cancel", type: "button", **on(:cancel) %>
  <% end %>
<% end %>
```

- After each render the client calls `showModal()` or `close()` to match
  `open:`. A refused save leaves the state set, so the dialog stays open.
- `on` hears a dialog's `cancel` (Escape, before it closes) and `close`
  (after every close). Put `on(:cancel, event: :cancel)` on the dialog so
  Escape clears the channel's state.
- A morph keeps the dialog's `open` attribute. `broadcast_morph` keeps the
  element; `broadcast_replace` swaps in a new one, which the client opens
  again while `open:` is true.
- A `focus` field inside the dialog takes the cursor on the render that
  opens it, and focus returns to the opener on close.
- Keep typed values out of the effect that renders the dialog
  (`Hibiki.untrack`), or each keystroke redraws it.
- Tailwind's reset removes a dialog's centering margin; add `m-auto`.

Full docs: https://planetaska.github.io/hibiki/commands/
