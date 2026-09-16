# Advanced usage

## Untracked reads: `peek` and `Hibiki.untrack`

An effect should never depend on a signal it writes, because its own write wakes it again and the loop ends in `SystemStackError`.

| Tool | Scope | Notes |
|---|---|---|
| `signal.peek` | one signal | returns the value, registers no edge; on a dirty derived it still recomputes, so the value is fresh |
| `Hibiki.untrack { }` | every read in the block | returns the block's result; hides reads only, so an effect created inside is still adopted by the current owner |

```ruby
count   = state(0)
history = state([])

effect { history.value = history.peek + [count.value] }   # depends on count alone
count.value = 1
count.value = 2
history.value # => [0, 1, 2]
```

Use `untrack` when the reads come from several signals, or happen inside a method the effect calls. An untracked read still sees the live value; it only skips the subscription.

## Batching

`batch { }` (or `Hibiki.batch`) applies writes immediately and defers effect runs, deduplicated, until the outermost batch exits.

- Reads inside the block see the new values at once; deriveds stay lazy dirty flags.
- Batches nest; only the outermost flushes, so a method that batches its own writes is safe to call from inside another batch.
- A raise inside the block still flushes, because the writes before it have already landed; effects catch up before the error reaches your `rescue`.
- A plain write is a batch of one, so a diamond (one state feeding two deriveds feeding one effect) runs the effect once per write.

```ruby
batch do
  first.value = "Barbara"
  last.value  = "Liskov"
end # the effect reading both prints "Barbara Liskov", once
```

## Custom equality: `equals:`

Both `state` and `derived` accept it. The same comparator is consulted at the write (is this write a no-op?) and at the flush (did anything this effect read change?), so a change the comparator can see is never swallowed downstream.

| Setting | Meaning | Example |
|---|---|---|
| omitted / `nil` | `==` | the default |
| callable `(prev, next)` | truthy means unchanged, write skipped | tolerance: `state(20.0, equals: ->(a, b) { (a - b).abs < 0.2 })` |
| `false` | never equal, every write notifies | toast: `state(nil, equals: false)`; repeats of "Saved!" show twice |

```ruby
temperature = state(20.0, equals: ->(prev, nxt) { (prev - nxt).abs < 0.2 })
effect { puts "temperature: #{temperature.value}" }   # prints "temperature: 20.0"
temperature.value = 20.1                              # prints nothing
temperature.value = 21.0                              # prints "temperature: 21.0"

level = derived(equals: ->(a, b) { (a - b).abs < 0.01 }) { raw.value / peak.value }
```

Equality only ever sees assignments. Take an array out, `<<` to it, assign it back, and the comparator receives the same object on both sides. `equals: false` still notifies there; the better fix is a new object (`tags.value += ["b"]`).

## Lifecycle: `on_cleanup` and `root`

- `on_cleanup { }` registers a teardown block on the current owner (the running effect or root). It runs before the owner's next re-run and again on `dispose`. Outside any owner it warns and registers nothing.
- `effect.dispose` finishes an effect: cleanups run, and it never runs again, even one already queued in a batch.
- An effect created inside another effect is owned by it and disposed on the owner's re-run or disposal.
- `root { |root| }` gives top-level effects an owner that never re-runs. It both yields and returns the root; dispose it when the session or connection it stands for ends.
- A root's block runs untracked, and a root is never adopted, so an enclosing effect's re-run or disposal leaves it alone.

```ruby
topic = state("news")
watcher = effect do
  name = topic.value
  puts "subscribed to #{name}"
  on_cleanup { puts "unsubscribed from #{name}" }
end                      # prints "subscribed to news"
topic.value = "sports"   # prints "unsubscribed from news", then "subscribed to sports"
watcher.dispose          # prints "unsubscribed from sports"

session = root do
  effect { puts "a sees #{topic.value}" }
  effect { puts "b sees #{topic.value}" }
end
session.dispose          # both effects gone, cleanups included
```

See `lifecycle-in-detail.md` for the owner tree and teardown order.

Full docs: https://planetaska.github.io/hibiki/advanced-usage/
