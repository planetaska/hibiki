---
title: Channel lifecycle
nav_order: 11
---

# Channel lifecycle

This page follows one channel subscription from the moment a browser
opens it to the moment it closes, and explains what
`include Hibiki::Rails::Channel` does at each step. You need none of it
to use the gem. Read it when you want to know which thread your code
runs on, why a value you set in one action is missing in the next, or
before you override `subscribed` or `unsubscribed` yourself.

A quick orientation for newcomers. In a hibiki_rails app, *signals* are values
the server holds for one page, and *effects* are blocks that re-run
whenever a signal they read changes; together they form the page's
*graph* ([Getting started]({{ "/getting-started/" | relative_url }})
introduces both). Each browser tab that subscribes to a channel gets its
own graph. The channel builds it in `build_graph` when the subscription
opens, changes it in response to actions from the browser, and discards
it when the subscription closes.

## One thread per graph

ActionCable runs incoming commands on a pool of worker threads, and it
makes no promise about order: two actions from the same tab can run on
two threads at once. Hibiki's signals cannot be shared that way. The
core gem has no locks; it stays safe by *confinement*, which means a
graph is only ever touched from one thread (see
[Threading model]({{ "/threading-model/" | relative_url }})).

The concern reconciles the two by giving every subscription its own
worker thread, called the *graph thread* on this page (the class is
`GraphActor`). Cable threads never touch the graph. Instead they *post*
closures to the graph thread, which runs them one at a time in the order
they arrived. The graph is built, changed, and disposed on that one
thread, and nowhere else. Everything below is a consequence of that
rule.

## When the browser subscribes

The subscription must carry a `cid` parameter, the per-page-load id the
page's JavaScript sends when it opens the channel. Without one, the
concern rejects the subscription, so a client that opens the channel by
hand with no `cid` gets nothing.

With one, the concern starts the graph thread and posts your
`build_graph` to it, wrapped in `Hibiki.root`. A root is an ownership
scope: every state, derived, and effect you create inside it belongs to
the root, so disposing the root later disposes all of them at once.
Each effect runs once immediately as it is created. That first run
reads whatever signals the block uses, and every read subscribes the
effect to that signal. Because this happens on the graph thread, so
does every re-run afterward.

## When an action arrives

Actions are the public methods on your channel, and the browser calls
them by name. The concern intercepts every call and posts the whole
action body to the graph thread, wrapped in one `Hibiki.batch`. A batch
lets writes land immediately but holds effect re-runs until the batch
ends, and runs each affected effect once. So an action that writes five
signals still means one re-run, and one re-render, per effect that read
any of them.

`rescue_from` handlers work as in any channel. The only difference is
where they run: on the graph thread, because that is where the action
body runs. An error no handler catches is reported to `Rails.error`
with the source `"hibiki_rails"`. The full picture, including errors
raised inside effects, is in
[Error handling layers]({{ "/error-handling-layers/" | relative_url }}).

When the batch ends, the channel sends the browser an acknowledgement.
The packaged client uses it to clear the island's busy state, and
[Loading state]({{ "/loading-state/" | relative_url }}) explains why it
waits for that rather than for new HTML.

## Every job starts clean

Building the graph, running an action, and flushing effects are each
one *job* on the graph thread, and each job runs inside
`Rails.application.executor`, the same wrapper Rails puts around a
request. That is what makes a thread that lives as long as the
subscription safe: code can autoload while the thread is running, and
each job gets a fresh Active Record query cache.

The consequence with teeth is that **`ActiveSupport::CurrentAttributes`
reset between jobs**. If an action sets `Current.user`, the next action
starts with it unset. Nothing set on a cable thread reaches the graph
thread at all, since the two never share a job. So a channel cannot
assign request-like context once and expect it to persist. Derive it at
the point of use instead, from the connection identity that
`ActionCable::Connection` already established when the browser
connected:

```ruby
def archive(data)
  # current_user comes from the connection's identified_by;
  # Current.user was reset when this job started
  current_user.todos.find(data["id"]).update!(archived: true)
  @todos.value = current_user.todos.map(&:attributes)
end
```

The last line copies the rows into plain hashes before writing the
signal. [Working with ActiveRecord]({{ "/working-with-active-record/" | relative_url }})
explains why a record itself must not cross into a signal.

## When the browser unsubscribes

The concern posts a dispose of the root to the graph thread, then closes
the thread's queue. Closing the queue rather than emptying it means
every job already posted still runs, in order, so an action that was in
flight completes before the dispose runs. Disposing the root runs every
`on_cleanup` block registered in the graph and drops every subscription
the effects held. Once the queue is empty, the thread exits.

A user navigating away can always race a click they have just made.
That action reaches the channel after the queue has closed, and the
concern drops it quietly rather than raising on a cable thread. The
browser gets an acknowledgement marked as dropped, so the client knows
nothing is coming for that action.

## Overriding the hooks

`subscribed` and `unsubscribed` are where the concern does its work, so
a channel that overrides either must call `super`. Skipping it in
`subscribed` leaves you with no graph; skipping it in `unsubscribed`
leaks a thread per closed tab.

Neither hook, and not `build_graph` either, is ever an action the
browser can call. ActionCable normally treats every public method a
channel adds as an action, so a public override of one of these would
be reachable from any client. The concern removes all three from the
action list, so you can make the override public without exposing it.

## When code reloads in development

Effects hold blocks written against the class versions that existed
when the graph was built. If a graph survived a code reload, those
effects would keep running the old code forever. So before Rails
reloads, an engine hook closes every cable connection that has a live
hibiki channel. Each channel then goes through the normal unsubscribe
path above: nothing is torn down by a second route.

Cable clients reconnect on their own, resubscribe, and `build_graph`
runs again on the fresh classes. Graph state lives in memory for the
life of a subscription, so it resets with it, just as a remounted
component would. Expect it in development, and remember it when a
counter jumps back to zero after you edit a file.
