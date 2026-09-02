---
title: Lifecycle in detail
nav_order: 2
---

# Lifecycle in detail

Hibiki's lifecycle model is an owner tree: every effect and every root
is an **owner**, and whatever gets created while its block runs — child
effects, cleanup blocks — belongs to it and is torn down with it. This page
spells out the exact rules; the short version lives in the
[Advanced Usage guide]({% link _guides/advanced-usage.md %}).

## The owner tree

While an effect (or a root's block) is running, it is the *current owner*.
Effects created during that window are adopted by it and disposed whenever
the owner re-runs or is disposed:

```ruby
outer_dep = state(0)
label = state("a")

effect do
  outer_dep.value                         # the outer effect depends on this
  effect { puts "label: #{label.value}" } # adopted by the outer effect
end
# prints "label: a"

label.value = "b"   # only the inner effect re-runs — prints "label: b"
outer_dep.value = 1 # the outer effect re-runs: the old inner effect is
                    # disposed and a fresh one is created ("label: b")
```

Without adoption, every outer re-run would leak a live duplicate of the
inner effect, and stale copies would keep firing forever.

One subtlety: `Hibiki.untrack` suppresses only dependency *registration*.
The owner slot is left alone, so effects created inside an `untrack` block
are still adopted and torn down normally.

## When an effect re-runs

An effect re-runs when something it read changed — and only then. A write does
not schedule effects directly; it invalidates, and the decision to run is made
at the end of the outermost batch (every write is an implicit batch of one, so
an unbatched write decides as it returns):

1. the write lands, or doesn't: `State#value=` returns early on an `==` value,
   so an equal write notifies nobody;
2. invalidation propagates — deriveds mark themselves dirty and pass it on,
   effects are queued and deduplicated;
3. at the flush, each queued effect compares every value it read on its last
   run against that value now. A dirty derived recomputes here to answer the
   question. If everything compares `==`, the effect does not run, and if it
   has a scheduler, the scheduler is not called either.

So the same value arriving by a new route is not a change:

```ruby
version = state(0)
names = derived { version.value; load_names } # re-reads on every bump
effect { render(names.value) }

version.value += 1 # names re-loads; if the list is equal, nothing renders
```

This is the gate Svelte's `$derived` has, placed on the reading side because a
derived has already told its subscribers to run by the time it knows its new
value. Two rules follow from it:

- **A derived's block must not have side effects.** The gate may recompute a
  derived to find out whether it changed, so the recompute can happen outside
  the effect that reads it — anything the block creates or registers belongs to
  whichever effect's gate asked. Deriveds are values, not owners.
- **`Effect#run` bypasses the gate.** A scheduler holding a deferred re-run
  runs the block when it calls `run`, no questions asked.

## What a re-run tears down

Before an effect re-runs (and likewise when it is disposed), in this order:

1. **Owned children are disposed first**, so a child's cleanup can still use
   a resource the parent's own cleanup is about to release.
2. **Its own cleanups run**, newest first — LIFO, like nested `ensure`
   blocks.
3. On a re-run only: **dependencies are re-collected from scratch**. The
   block runs again and subscribes to exactly what it reads *this* time, so
   the stale branch of a dynamic dependency (`flag ? a.value : b.value`)
   stops invalidating it.

## `on_cleanup`

`Hibiki.on_cleanup { }` registers a teardown block on the current owner —
the innermost running effect or root. It runs before that owner's next
re-run and when the owner is disposed, which makes it the home for anything
an effect acquires:

```ruby
effect do
  socket = connect(url.value)
  Hibiki.on_cleanup { socket.close } # old socket closed before each reconnect
end
```

Two details worth knowing:

- The owner is a separate slot from the tracking listener. A lazy derived that happens to recompute in the middle of an
  effect registers its `on_cleanup` calls on the *effect* — deriveds are
  values, not owners, and never own anything.
- Called outside any effect or root, the cleanup could never run. Hibiki
  warns and drops the block rather than raising.

## Roots escape the tree

`Hibiki.root` is the deliberate exception to adoption. Its block runs
untracked — signals read while building the graph do not subscribe an
enclosing effect — and a root created inside a running effect is **not**
adopted by it. The root's lifetime is exactly `Hibiki.root` …
`root.dispose`, no matter where it was created:

```ruby
watcher = state(0)
session = nil

effect do
  watcher.value                        # this effect re-runs on writes
  session ||= Hibiki.root do
    effect { puts "still alive" }      # survives the outer effect's re-runs
  end
end

watcher.value = 1  # outer re-runs; the root and its effect are untouched
session.dispose    # the only way this graph comes down
```

This is the escape hatch from the owner tree: whoever holds the root
object owns its teardown, which is what you want for graphs whose lifetime
is an external event — a session, a connection — rather than a re-run.

`Hibiki.root { |root| ... }` both yields and returns the root, since in Ruby
the caller, not the block, typically holds on to it.

## Disposal is final

Roots and effects both expose `#dispose` and `#disposed?`. Disposing walks
the same teardown as a re-run — children first, then cleanups — and an
effect additionally severs every subscription, so nothing can invalidate it
again.

`dispose` is idempotent, and a disposed effect never runs again under any
circumstance: not from a write, not from a batch flush it was already queued
in, and not from a scheduler firing a deferred re-run late. Dispose always
wins the race.

You rarely need `Effect#dispose` directly — the owner tree handles nested
effects, and roots handle everything long-lived — but it is there for the
odd effect whose lifetime matches neither.
