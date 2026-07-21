---
title: Advanced usage
nav_order: 4
---

# Advanced usage

## Untracked reads

Sometimes an effect should *sample* a signal without depending on it.
`Hibiki.untrack { }` suppresses dependency registration for a block, and
`#peek` is the per-signal shorthand — the classic use is read-modify-write,
where an effect must not depend on the signal it writes:

```ruby
count = state(0)
history = state([])

# Log every count change — without peek, writing history would re-trigger
# this effect forever (it would depend on its own output).
effect { history.value = history.peek + [count.value] }
```

## Batching

`batch { }` (or `Hibiki.batch { }`) applies writes immediately but defers and deduplicates effect runs until the outermost batch exits. This is useful when you have several related writes, and you want to trigger affected effect only once (instead of triggering the effect once per write):

```ruby
first = state("Ada")
last  = state("Lovelace")
effect { puts "#{first.value} #{last.value}" } # prints "Ada Lovelace"

batch do
  first.value = "Grace"
  last.value  = "Hopper"
end # prints "Grace Hopper" — once, not twice
```

## Lifecycle: `root` and `on_cleanup`

Effects created while another effect runs are *owned* by it and disposed automatically when the owner re-runs or is disposed. For everything else there is `Hibiki.root` (Solid's `createRoot`): an ownership scope you tear down yourself — the anchor for long-lived graphs (a session, a connection) whose teardown is an external event.

`Hibiki.on_cleanup` (Solid's `onCleanup`) registers teardown on the owning effect or root; it runs before each re-run and on dispose. In other words, this is the place to release timers, sockets, subscriptions an effect sets up:

```ruby
interval = state(1)

ticker = Hibiki.root do
  effect do
    timer = start_timer(every: interval.value)
    Hibiki.on_cleanup { timer.cancel } # runs before each re-run, and on dispose
  end
end

interval.value = 5 # old timer cancelled, new one started
ticker.dispose     # tears down every effect in the scope, cleanups included
```

A root's block runs untracked, and a root created inside an effect is *not* adopted by it — it deliberately escapes the automatic owner tree, so its lifetime is exactly `Hibiki.root` … `root.dispose`. Individual effects can still be disposed directly with `Effect#dispose`. Refer to the [Lifecycle reference]({% link _references/lifecycle-in-detail.md %}) if you wish to know more about Hibiki's lifecycle.

## Where to next

- [Threading model]({{ "/threading-model/" | relative_url }}) —
  fiber-confined bookkeeping, what is and isn't isolated across threads,
  fibers, and Ractors.
- [Why no transparent signals?]({{ "/why-no-transparent-signals/" | relative_url }}) —
  the rejected transparency designs, with the failure cases spelled out.
- [Status & limitations]({{ "/status-and-limitations/" | relative_url }}) —
  what the signal core already guarantees.