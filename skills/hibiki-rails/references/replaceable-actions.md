# Replaceable actions

Since 0.21.0. When a server falls behind, a visitor typing in a live search
queues search after search, and every one runs, renders and is sent though
only the newest matters. A replaceable action is skipped when a newer one of
its kind is right behind it. Two halves, declared apart; each works alone.

## The channel's half

```ruby
class SearchChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  replaceable :search, :set_sort, :set_filter, :go_to_page
end
```

- An action is skipped only when the NEXT action the browser sent on that
  subscription is the same kind and the first has not started. "Next" is by
  the client's numbering (since 0.20.1 the channel runs actions in the order
  sent), not by arrival.
- The kind is the action name plus the payload's keys. `on(:set_field, event:
  :input)` on every field of a form sends `{ "name" => ... }` or `{ "notes" =>
  ... }`: two kinds, so one field never replaces another.
- Only the action right behind counts: `search("ab")`, `save`,
  `search("abc")` all run, so the save sees the query the visitor saw.
- A started action runs to the end. An action with no `hbk` number (app code
  calling the subscription directly) is never skipped and sits between the
  two around it.
- A skipped action never runs: no `Hibiki.batch`, no `rescue_from`, no
  `action` event. It is acked `{ ack: seq, dropped: true }` (clients since
  0.20.1 settle that at once) and publishes `skip.hibiki_rails` (`channel`,
  `action`, `wait`). Trips it carried are still published.
- Names are checked at subscribe (ArgumentError naming the bad one), so the
  macro may sit above the methods. A subclass adds to its parent's list. The
  macro adds no client-callable action.

Declare only actions that set state outright from their payload: a search, a
sort, a filter, a page. Never one that adds (increment, add a row), toggles,
saves, or reaches outside the graph (sends mail): skipping it loses what the
visitor asked for.

## The browser's half

```erb
<%= tag.input type: "search", name: "q", **on(:search, event: :input, replaceable: true) %>
```

- While an action of that kind from the island waits for its ack, a new one
  is held; a newer one replaces the held one. The ack (dropped or not), or a
  stall, sends the newest held.
- Any other action from the island sends what is held first, oldest first,
  so a click never overtakes the search typed before it. That includes
  `perform()` and `performOn()` from app JS.
- A held send takes its `hbk` when it goes. Its control stays busy while held.
  Held sends are dropped when the link drops.
- Generic islands only (the `hibiki` controller), not `ChannelController`
  subclasses. `on` raises for it with `event: :popstate` or a `js` command
  list.
- It complements `debounce:`: the debounce waits for the visitor, the hold
  waits for the server. On a server keeping up the ack takes 10 to 40 ms, so
  the hold is rarely felt.

## What it buys, and what it cannot

Measured on one Puma process at its one-core ceiling (about 430 searches a
second), 500 visitors each searching once a second: with neither half the
queue grew without end (mean wait 22 s); the channel's half kept wait under
the visitors' one-second interval (mean 0.25 s); both halves left no queue
at all (under 1 ms). Neither raises the ceiling: with 500 searches in flight
and about 415 finished a second, each still takes about 1.2 s. More Puma
workers raise it.

The scaffold's channel declares `replaceable :search, :go_to_page, :set_sort,
:set_filter` (no `:search` under `--skip-search`) and its search box carries
`replaceable: true`.

Full docs: https://planetaska.github.io/hibiki/replaceable-actions/
