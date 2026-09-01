---
title: Introduction
nav_order: 1
---

# Rails introduction

Hibiki is a library of *signals* for Ruby. A signal is a value that
remembers who read it. You write a value with `state`, compute from it with
`derived`, and react to it with `effect`; when the state changes, every
derived value and effect that read it re-runs on its own. You never declare
what depends on what. If signals are new to you, the
[core introduction]({{ "/introduction/" | relative_url }}) shows all three
primitives in a dozen lines. The core gem is plain Ruby with no opinion
about the web.

The sister gem `hibiki_rails` puts those signals to work in a Rails app. The
idea is this: keep the state of an interactive part of a page on the
server, in signals, and let effects re-render the HTML whenever that state
changes. The browser keeps no state of its own. It sends the user's clicks
and form input to the server and swaps in the HTML that comes back. You
write Ruby, and the page updates.

## What happens on a click

Every interaction is one round trip, and every round trip follows the same
four steps:

```
1. the browser sends an action to the server over ActionCable
2. the action writes one or more signals
3. the effects that read those signals re-render their fragments
4. the new HTML travels back down and replaces the old fragment
```

Steps 2 and 3 are ordinary Hibiki. An effect subscribes to the signals it
reads, so only the effects whose inputs changed re-render. A click that
changes one number re-renders one fragment, and nothing else moves.

Steps 1 and 4 are the gem's work. It ships a small JavaScript client that
sends actions up and swaps fragments in, so you write no JavaScript of your
own. The HTML can come back down two ways. It can be broadcast as Turbo
Streams to a named stream, which Turbo's own JavaScript applies. Or the
channel can send it directly over its own subscription, and the packaged
client swaps each fragment in by its DOM id. [The JS client]({{
"/the-js-client/" | relative_url }}) covers both.

## One graph per browser tab

The signals, derived values, and effects wired together make up a *graph*.
In `hibiki_rails`, an ActionCable channel owns the graph: it builds the
graph when the browser subscribes and disposes it when the browser
unsubscribes. Each subscription gets its own graph, and in practice a
subscription is a browser tab. Two tabs never share state, and closing a
tab frees everything it used.

## Phlex

For apps that render views with Phlex instead of ERB, a second sister gem,
`hibiki_phlex`, makes a Phlex component itself reactive. The component
declares its signals as class-level fields and reads them as ordinary
methods, and one render effect re-renders the whole component whenever any
of them change. See [Phlex support]({{ "/phlex-support/" | relative_url }}).

## Requirements

`hibiki_rails` needs Rails 8.0 or later and Ruby 3.4 or later. It depends
on the core `hibiki` gem and on `turbo-rails`.

Next step: visit the [quick start]({{ "/rails-quick-start/" | relative_url }}) to install the gem and generate your first reactive component.
