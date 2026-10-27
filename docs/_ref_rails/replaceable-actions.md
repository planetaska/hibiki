---
title: Replaceable actions
nav_order: 14
---

# Replaceable actions

This page covers *replaceable actions*, added in 0.21.0: a way to tell the
channel that a newer search, sort or page number makes an older one still
waiting pointless, and to tell the browser to send fewer of them while the
server is busy. Read it when a live search, a filter bar or a sortable list
has to hold up under load, or when you add an action to a scaffolded
channel's `replaceable` list and want to know what the list means.

Every reactive change in a `hibiki_rails` app is a round trip, and a
channel runs one subscription's actions one at a time, in the order the
browser sent them ([Channel lifecycle]({{ "/channel-lifecycle/" | relative_url }})
explains the thread they run on). While the server keeps up, that is all
there is to it. When it falls behind, a visitor typing in a live search
queues a search for each pause in their typing, and every one of them
runs, renders and is sent down, though only the newest matters: the
page draws each result and then draws the next one over it at once. The
wasted work is what keeps the backlog from draining, since the server
spends its time on results nobody will see.

Replaceable actions take that work away in two places. The channel skips
an action that the next one has already made pointless, and the browser
holds a new search while the last one is still being answered, so the
queue never forms. The two halves are declared separately, and each works
on its own.

## The channel's half: `replaceable`

A class macro on the channel names the actions a newer one may replace:

```ruby
class SearchChannel < ApplicationCable::Channel
  include Hibiki::Rails::Channel

  replaceable :search, :set_sort, :go

  def build_graph
    @query = Hibiki::State.new("")
    ...
  end

  def search(data)
    @query.value = data["q"].to_s
  end
  ...
end
```

Here `search` sets the query from its payload and nothing it does depends
on the query before it, so a search the visitor has already typed past
can be left out. The macro says so for `search`, `set_sort` and `go`.
From then on:

- **An action is skipped when the next one is of its kind and it has not
  started.** The browser numbers its actions, and since 0.20.1 the channel
  runs them in that order, so "the next one" means the next action the
  browser sent on that subscription. If `search("ab")` is still waiting
  when `search("abc")` arrives, `search("ab")` never runs.
- **The kind is the action's name and the payload's keys.** An inline edit
  form puts `on(:set_field, event: :input)` on every field, and each send
  carries only its own field, `{ "name" => ... }` or `{ "notes" => ... }`.
  Those are two kinds, so a send for one field never replaces a send for
  another.
- **Only the action right behind counts.** With `search("ab")`, `save`
  and `search("abc")` queued, all three run, so the save runs against the
  query the visitor saw on the page when they pressed Save.
- **An action that has started runs to the end.** Nothing is cancelled.
- **A skipped action never runs.** There is no `Hibiki.batch`, no
  `rescue_from` and no `action.hibiki_rails` event for it. The browser gets
  its acknowledgement marked as dropped, which every client since 0.20.1
  settles at once, so the control stops being busy. The channel publishes
  `skip.hibiki_rails` instead, with the `channel`, the `action` and the
  `wait`, the milliseconds the action stood in line
  ([Instrumentation]({{ "/instrumentation/" | relative_url }}) lists the
  events). The trips the browser sent with the action are still published
  as `trip` events.
- **The names are checked when a browser subscribes.** The methods may be
  defined below the macro, so it cannot check them at class load. A name
  that is not an action raises an `ArgumentError` naming it. A subclass
  adds to its parent's list.

The macro adds nothing a client can call. The actions it names are the
public methods you already wrote.

### What to declare

An action qualifies when it sets state outright from its payload, so that
running the newest one leaves the graph as if the older ones had run too.
A search, a sort, a filter and going to a page are the usual cases: the
payload says what the value should be, and the action writes it.

**Never declare an action that adds, toggles, saves or has an effect
outside the graph.** An increment, an "add a row", a checkbox toggle, a
save or an action that sends mail each do something the visitor asked for
once and expects once. Skipping one loses that request. Two increments
queued behind each other are two increments, and a visitor who clicked
twice meant both.

## The browser's half: `replaceable: true`

The channel's half stops the work once a queue exists. The browser's half
keeps the queue from forming. `on` takes `replaceable: true`, here on a
search box:

```erb
<%= tag.input type: "search", name: "q", **on(:search, event: :input, replaceable: true) %>
```

The field sends `search` with `{ q: ... }` on each pause in typing, as
any `:input` control does. The option changes what happens while the
server has not yet answered the last one:

- **A new send is held while one of its kind is in flight.** The kind is
  the same as the channel's: the action name and the payload's keys. The
  island waits for the acknowledgement of the search it already sent, and
  only then sends the next.
- **A newer send replaces the held one.** Type three more letters during
  one slow search and one search leaves when the acknowledgement arrives,
  with the latest text. The acknowledgement sends it whether or not the
  server dropped the action it answers, and so does a stall.
- **Any other action from the island sends what is held first, oldest
  first.** A click on Sort made after the visitor typed sends the held
  search before the sort, so a click never overtakes the search typed
  before it. This includes an action your own JavaScript fires with
  `perform` or `performOn`
  ([Driving an island from JS]({{ "/driving-an-island/" | relative_url }})).
- **A held send takes its sequence number only when it goes.** The
  numbers the channel orders by stay without gaps.
- **The control stays busy while its send is held.** The trip in flight
  already marks it, so the field shows the same
  [loading state]({{ "/loading-state/" | relative_url }}) it would for a
  slow trip.
- **A held send is dropped when the connection drops**, like everything
  else that is in flight in that gap
  ([Driving an island from JS]({{ "/driving-an-island/" | relative_url }}#accepted-or-dropped-the-return-value)
  explains why nothing queues across it).

The option works on the generic island, the `hibiki` controller. A
`ChannelController` subclass of your own does not hold sends. `on`
refuses `replaceable: true` on `event: :popstate` and on a list of
commands built with `js`, since neither is an action a newer one could
replace.

### The debounce and the hold

A search box already waits, through its debounce, and the two waits are
for different things. The debounce waits for the visitor: an `:input`
control sends nothing until typing pauses for 250 ms. The hold waits for
the server: once a search is on its way, the next one waits for the
answer. On a server that keeps up, an acknowledgement takes 10 to 40 ms,
so the hold is over before the next pause in typing and the visitor never
feels it. On a server that has fallen behind, each tab sends one search
per answer rather than one per pause, and the server's queue stays short.

## The two halves together

Each half works alone. `replaceable: true` on a control works with any
channel, since it only changes when the browser sends; the channel's list
is what the server skips by, and it applies to sends from any client since
0.20.1, which numbers its actions. Use
both on a control that qualifies, as the scaffold does.

What the two halves buy, measured on one process on a 12-core Mac with
Ruby on one core, running reverb's Live Search recipe for 500 visitors who
each search once a second. That rate is past the process's ceiling of
about 430 searches a second, so the server is behind from the first
second:

- **With neither half**, the queue grew without end. The mean wait for an
  action went from 10.5 s to 21.9 s over two minutes, and an
  acknowledgement took 6.2 s at the median.
- **With the channel's half alone**, the queue stopped growing. The mean
  wait was 0.25 s and never more than one second, which is the visitor's
  own interval. Acknowledgements took 1.2 s at the median, and 15% of the
  searches were skipped.
- **With both halves**, there was no queue: under a millisecond of wait,
  acknowledgements at 1.0 s at the median, and a render arriving 166 ms
  after its search at the 95th percentile, where the channel's half alone
  gave 755 ms.

What neither half can do is raise the ceiling. With 500 searches always in
flight and about 415 finished each second, each one takes about 1.2 s
from send to acknowledgement, because that is how long the line is. More
Puma workers raise the ceiling; replaceable actions keep the line from
growing past it.

## In a scaffolded app

A channel generated by `hibiki:rails:scaffold` or `scaffold_controller`
declares its query actions:

```ruby
# app/channels/books_channel.rb
replaceable :search, :go_to_page, :set_sort, :set_filter
```

Under `--skip-search` the list has no `:search`. The generated search box
carries `replaceable: true`. A filter's payload names its column, so two
filter columns are two kinds, and a change to one never skips a change to
the other.

When you add an action of your own to that list, check that it sets state
outright from its payload, as the section [What to declare](#what-to-declare)
describes. [CRUD scaffolding]({{ "/crud-scaffolding/" | relative_url }})
covers the rest of the generated channel.
