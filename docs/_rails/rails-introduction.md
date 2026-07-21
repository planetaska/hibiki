---
title: Introduction
nav_order: 1
---

# Rails introduction

Rails integration comes from the sister gem `hibiki_rails`: connection-scoped signal graphs over ActionCable, pushing re-rendered HTML to the page — either through Turbo Streams, or over the channel's own subscription to the gem's packaged client (see [The JS client]({{ "/the-js-client/" | relative_url }})).

```
cable action arrives → mutate signals → effects render partials →
Turbo Streams broadcast → Turbo morphs the DOM
```

A graph lives per cable connection (in practice: per browser tab): it is built when the channel subscribes and disposed when it unsubscribes. Effects subscribe to whatever signals they read, so when an action writes a signal, exactly the affected effects re-render and broadcast — nothing else moves.

For Phlex apps, a second sister gem, `hibiki_phlex`, turns Phlex components into reactive components with a render effect per component (see [Phlex support]({{ "/phlex-support/" | relative_url }})).

Supports Rails >= 7.1, Ruby >= 3.4.
