---
title: Commands and dialogs
nav_order: 7
---

# Commands and dialogs

This page covers two things added in 0.20.0: commands, which let a control
change the page in the browser without asking the server, and the helpers
that open and close a `<dialog>`. Read it when a click should open a menu,
add a class, or move focus at once, or when a form belongs in a modal.

Everything else in `hibiki_rails` is a round trip: the browser sends an
action, the channel writes signals, and HTML comes back. That is right for
state the server owns. It is slow and wasteful for state only the browser
cares about, such as whether a menu is open. A command handles that state
where it lives.

## Setup

Commands are run by a small module that the page must import once, beside
its controllers:

```js
// app/javascript/application.js
import "hibiki-rails/commands"
```

`bin/rails g hibiki:rails:install` adds the line. An app installed before
0.20.0 adds it by hand, or runs the generator again; every step of the
generator is safe to repeat. Importmap apps resolve the name through a pin
the gem supplies, and bundler apps through the npm package.

Without the import a command does nothing, and the client says so once in
the browser console.

## Writing a command

The `js` helper starts a list of commands, and `on` takes the list where it
would take an action name:

```erb
<%= tag.button "Menu", **on(js.toggle("#menu")) %>

<ul id="menu" hidden>
  ...
</ul>
```

A click on the button shows or hides the menu. Nothing is sent to the
channel.

Commands chain, and the browser runs them in the order written:

```erb
<%= tag.button "Cancel", **on(js.hide("#panel").push(:cancel)) %>
```

This hides the panel at once and then performs the channel's `cancel`
action. The browser does not wait for the server between commands.

| command | what it does |
| ------- | ------------ |
| `show(target)`, `hide(target)`, `toggle(target)` | removes, adds, or flips the `hidden` attribute |
| `add_class(names, to:)`, `remove_class(names, to:)`, `toggle_class(names, to:)` | one or more class names, as a string or an array |
| `set_attribute(name, value, to:)`, `remove_attribute(name, to:)` | writes or removes an attribute |
| `toggle_attribute(name, value = "", to:)` | sets the attribute when it is absent and removes it when present |
| `focus(target)` | focuses the target |
| `focus_first(target)` | focuses the first link, button, or field inside the target |
| `dispatch(name, to:, detail:, bubbles: true)` | fires a `CustomEvent` for your own JavaScript to hear |
| `push(action, with:)` | performs a channel action |
| `show_modal(target)`, `close_dialog(target)` | opens or closes a `<dialog>`; see [Dialogs](#dialogs) |

### Targets

A target says which elements a command acts on. It takes one of four forms:

- **Nothing.** The command acts on the control itself.
- **A CSS selector**, such as `"#menu"` or `".row"`. The browser looks it
  up in the whole document, and the command acts on every match.
- **`{ inner: selector }`.** Every match inside the control.
- **`{ closest: selector }`.** The control's nearest ancestor that matches.

```erb
<%= tag.button "Mark", **on(js.add_class("done", to: { closest: "li" })) %>
```

Commands that only need a target take it as their argument. The others
take it as `to:`, after their own arguments.

### Sending an action

`push` performs a channel action from inside a list. It behaves as the
action form of `on` does: the control shows the busy mark until the server
answers, a submitted form adds its fields to the payload, and a changed
field adds its value. The payload of the action goes on `push`:

```erb
<%= tag.button "Archive", **on(js.hide({ closest: "li" }).push(:archive, with: { id: note.id })) %>
```

The options of `on` apply to the whole list. With `confirm:`, declining
runs no command at all. With `debounce:`, the list waits and then runs
together. `fallback: true` needs a `push` in the list, since the fallback
is what stands in for the action. A list accepts every event an action
does, keys included: `on(js.hide("#panel"), event: "keydown.esc")`.

## Rules

- **A command's change lasts until the server next renders that element.**
  A replace swaps the element for a new one, and a morph sets its
  attributes back to the ones in the server's HTML. Use commands on
  elements the channel does not render, or accept that a render resets
  them. State the server should know belongs in a signal.
- **A list prevents the event's default.** A link wired with a list does
  not navigate, and a form does not submit.
- **One control takes one list.** `on` returns a single list or a single
  action, never both. Put the action in the list with `push`.
- **Commands run only on a control inside an island.** Their targets may be
  anywhere on the page.
- **`hidden` can lose to your CSS.** A rule that sets `display` on the
  element overrides the attribute in plain CSS. Tailwind 4's reset makes
  `hidden` win.
- **Some attributes are refused.** `set_attribute` and its siblings will
  not write an attribute that begins with `on`, nor `style`, `srcdoc`,
  `data-controller`, `data-action`, or any `data-hibiki-*` attribute.
- **Mistakes raise when the view renders.** A refused attribute, an empty
  list, a target that is not one of the four forms, and `with:` beside a
  list each raise an `ArgumentError`.

`dispatch` is the way out when a command is not enough. It fires an event
that your own Stimulus controller or script can hear, so a third-party
widget can be opened from the same list that hides a panel. For the other
direction, your JavaScript sending an action to the channel, see
[Driving an island from JS]({{ "/driving-an-island/" | relative_url }}).

## Dialogs

A `<dialog>` opened with the browser's `showModal()` keeps focus inside
itself, closes on Escape, dims the page behind it, and returns focus to the
control that opened it. The gem gives two ways to open one. Choose by who
needs to know that the dialog is open, and use one way per dialog.

### A dialog the browser owns

For a menu, a help panel, or anything the server need not hear about, open
and close the dialog with commands:

```erb
<%= tag.button "About", **on(js.show_modal("#about")) %>

<dialog id="about">
  <p>...</p>
  <%= tag.button "Close", **on(js.close_dialog) %>
</dialog>
```

`close_dialog` with no target closes the dialog the control is in.

### A dialog the server owns

A form in a dialog is different. The server may refuse the save, and then
the dialog must stay open; only the channel knows which. The `modal` helper
ties the dialog to the channel's state:

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

After each render the client compares the dialog with `open:` and calls
`showModal()` or `close()` to match. An action that sets the state opens
the dialog. A save that succeeds clears the state and closes it, and a
save the model refuses leaves it open with its errors.

Four things make this work as a visitor expects:

- **Escape reaches the channel.** A dialog's `cancel` event fires when the
  visitor presses Escape, just before the browser closes the dialog. `on`
  hears it, so `on(:cancel, event: :cancel)` clears the channel's state
  too. `on` also hears `close`, which fires after every close, whoever
  asked for it.
- **A morph keeps the dialog open.** The browser marks an open dialog with
  an `open` attribute that the server's HTML never has. The client stops a
  morph from removing it.
- **The first field takes the cursor.** A field marked with
  [`focus`]({{ "/the-js-client/" | relative_url }}#focus) inside the dialog
  is focused on the render that opens the dialog, and focus returns to the
  control that opened it when the dialog closes.
- **Typing does not redraw the dialog.** Keep the typed values out of the
  effect that renders it: read them with `Hibiki.untrack`, or render the
  dialog from the state that opens and closes it alone. Otherwise each
  keystroke renders the dialog again.

The dialog may be drawn by `broadcast_morph` or by `broadcast_replace`. A
morph keeps the element and is the gentler of the two. A replace swaps in a
new dialog, which the client opens again when `open:` is still true.

Tailwind's reset removes the margin that centers a dialog. Add `m-auto` to
the dialog's classes to center it again.
{: .tip }

## What commands do not do

Commands are a first set. They have no timed steps or transitions: CSS
transitions on the classes and attributes they write cover the simple
cases, and [Motion explained]({{ "/motion-explained/" | relative_url }})
covers elements a render adds or removes. They do not survive a render of
their target, as the first rule says. And the channel cannot send one: a
command always starts from an event in the browser, so a change the server
decides on is still a render.
