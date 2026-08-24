---
title: Introduction
nav_order: 1
---

# Rails introduction

The sister gem `hibiki_rails` connects Hibiki to Rails. Your signals and effects run on the server; the browser sends actions over ActionCable and receives re-rendered HTML in return — through Turbo Streams, or over the channel's own subscription to the gem's packaged client (see [The JS client]({{ "/the-js-client/" | relative_url }})).

```
cable action arrives → mutate signals → effects render partials →
Turbo Streams broadcast → Turbo morphs the DOM
```

Each cable connection — in practice, each browser tab — gets its own signal graph. The channel builds the graph when it subscribes and disposes it when it unsubscribes. Effects subscribe to the signals they read, so when an action writes a signal, only the affected effects re-render and broadcast; nothing else moves.

For Phlex apps, a second sister gem, `hibiki_phlex`, makes Phlex components reactive, with one render effect per component (see [Phlex support]({{ "/phlex-support/" | relative_url }})).

`hibiki_rails` supports Rails >= 8.0 and Ruby >= 3.4.
