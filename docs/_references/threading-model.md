---
title: Threading model
nav_order: 1
---

# Threading model

A signal graph is a web of relationships: this effect listens to that derived, which listens to those two states. Hibiki builds the web by watching reads as they happen, and "who is reading right now" is a question that only has an answer within a single flow of execution. Ruby offers three ways to run more than one flow at a time, and they differ in what they share and when they switch. Those differences decide how Hibiki behaves, so this page introduces the three first, then explains what Hibiki keeps track of, and finally walks through how a graph lives on each.

## Three ways Ruby runs code side by side

Start with the process. When you run `ruby app.rb` or boot a Rails server, the operating system starts one Ruby process: a single running copy of the interpreter, with its own memory, where every object your program creates lives. Everything on this page happens inside that one process, and the three mechanisms below are the three ways Ruby divides its work up within it.

**A thread** is an independent flow of execution inside that process. Threads share everything: every object your program creates is visible to every thread. The standard Ruby interpreter runs one thread at a time and switches between them whenever it likes, in the middle of a method included, so two threads can interleave their work at any point. You meet threads constantly, whether or not you create them: a web server such as Puma handles each request on a thread of its own, and a job runner works its queue on several.

**A fiber** is a lighter, more polite cousin of a thread. It also runs a flow of code inside a process, but it runs only when something resumes it, and it stops only when it chooses to hand control back. Nothing interrupts a fiber, so fibers never race one another. Every thread has a root fiber that runs its main code, and Ruby creates further fibers on your behalf more often than you might think: `Enumerator#next` runs its block in one, and asynchronous IO libraries run every task in one.

Each fiber carries a small pocket of variables of its own, called fiber storage. Ruby offers two kinds of pocket, and the difference matters later on this page. Values kept in `Fiber[]` are *inherited*: a new fiber begins life with a copy of what its creator had. Values kept in `Thread.current[]` are, despite the name, also per fiber, but a new fiber starts with that pocket empty.

**A Ractor** is Ruby's way of running code in true parallel. Each Ractor has its own interpreter lock, and to make that safe, Ractors share almost nothing. An object is either shareable, meaning deeply frozen, or it belongs to exactly one Ractor. Hand an ordinary object to another Ractor and Ruby copies it, or refuses if it cannot. Ractors are still marked experimental, and most programs never create one.

| | Thread | Fiber | Ractor |
|---|---|---|---|
| Runs alongside its siblings | Takes turns, switched at any moment | Only when resumed, never interrupted | Yes, in true parallel |
| Shares objects with its siblings | Everything | Everything | Nothing mutable |
| Where you meet it | Web servers, job runners | `Enumerator`, async IO | Opt-in parallel work |

## What Hibiki keeps track of

While a derived or an effect is computing, Hibiki makes a note that it is *the one currently paying attention*. Every signal read during that window subscribes it. The moment the block returns, the note is erased. The [introduction]({% link _guides/introduction.md %}) shows this trick from the outside. Here we care about where the note is kept, because a note like this is not a fact about any signal. It is a fact about the flow of execution that is running right now. Three such facts exist:

- **the tracking window**: which derived or effect is computing right now;
- **the current owner**: which effect or root adopts the effects created right now, as described in [Lifecycle in detail]({% link _references/lifecycle-in-detail.md %});
- **the open batch**: how deep the current `batch` nesting is, and which effects are waiting for it to close.

Hibiki keeps all three in fiber storage, so each flow of execution has its own set and none can see another's. The signals themselves are ordinary Ruby objects with no lock inside. That combination, private bookkeeping and unlocked objects, is the whole design, and the three sections below spell out what it means for threads, fibers, and Ractors in turn.

## Threads: a graph lives on one thread

Every thread has a root fiber of its own, so every thread keeps its own note. Three guarantees follow:

- A read on another thread never subscribes your running effect.
- An effect created on another thread is never adopted by yours, so re-running yours leaves it alone.
- A batch you open defers only your own effects. A write on another thread runs its effects at once, even while your batch is open.

Here are two threads, each building a counter of its own:

```ruby
workers = 2.times.map do
  Thread.new do
    count = state(0)
    log   = []
    effect { log << count.value }
    batch { 5.times { count.value += 1 } }
    log
  end
end

workers.map(&:value) # => [[0, 5], [0, 5]]
```

Each thread built a graph, batched five writes, and saw its effect run twice: once on creation and once after the batch closed. Neither thread's batch held up the other's effect, and neither effect learned of the other's counter. Two graphs on two threads leave each other alone.

### Writing to a graph from another thread

Private bookkeeping is a different thing from shared signals. A state, a derived, or an effect is an ordinary Ruby object with no lock inside, so a graph is safe on one thread and unsafe under two. Svelte and Solid live in a browser with a single thread and never face the question; Hibiki adopts their worldview and asks you to give each graph a thread of its own.

A thread with news for a graph it does not own hands the news over rather than writing directly. The simplest arrangement is a `Queue` and one thread that owns the graph. hibiki_rails works this way under the hood: each incoming action is posted to the graph's own thread and applied there inside one batch.

```ruby
inbox = Queue.new

owner = Thread.new do
  count = state(0)
  effect { puts "count is #{count.value}" } # prints "count is 0"
  while (message = inbox.pop)
    count.value = message
  end
end

inbox << 1 # from any thread: prints "count is 1", on the owner thread
inbox << 2 # prints "count is 2"
inbox.close
owner.join
```

Writes arrive in order, each one lands on the owner's thread, and the graph never sees two threads at once.

## Fibers: the bookkeeping follows you in

Fibers are where the two kinds of fiber storage earn their keep. Hibiki keeps the tracking window and the current owner in the inherited pocket, `Fiber[]`, so they follow a read into an `Enumerator`, whose `next` runs the block in an internal fiber of its own:

```ruby
count   = state(1)
doubled = derived { Enumerator.new { |y| y << count.value * 2 }.next }

doubled.value # => 2
count.value = 5
doubled.value # => 10
```

The read of `count` happened in a fiber that the derived never created by hand, and the dependency registered all the same. Had the window lived in the empty-at-birth pocket, the edge would have been dropped in silence, and `doubled` would have stayed at 2 forever. The worst that inheritance can do is the opposite: a read inside a spawned fiber subscribes an effect to a signal it did not strictly need, which costs one extra run. That is the safe way to be wrong.

The open batch lives in the other pocket, `Thread.current[]`, and deliberately so. A batch belongs to the fiber that opened it and closes when that fiber leaves the block. A fiber started in the middle of a batch is therefore not batching, and its writes run their effects at once:

```ruby
count = state(0)
effect { puts "count is #{count.value}" } # prints "count is 0"

batch do
  Fiber.new { count.value = 1 }.resume # prints "count is 1" at once
  count.value = 2                       # deferred
end                                     # prints "count is 2"
```

Were the batch inherited, the fiber would begin inside a batch it can never close, and every effect it touched would wait in a queue for a flush that never comes.

## Ractors: one world per Ractor

A Ractor runs its own reactive world. Hibiki keeps no state in module-level variables, which is what raises an `IsolationError` off the main Ractor, so a complete reactive cycle runs inside one untouched:

```ruby
ractor = Ractor.new do
  log     = []
  count   = state(1)
  doubled = derived { count.value * 2 }
  effect { log << doubled.value }
  batch { count.value = 3 }
  log
end

ractor.value # => [2, 6]   (`ractor.take` before Ruby 3.5)
```

Signals are ordinary, unshareable Ruby objects. Hand one to a Ractor and Ruby either copies it, leaving the original untouched, or refuses outright once the signal has subscribers. Either way a graph never straddles the boundary, so the one-world-per-Ractor model holds without any help from Hibiki.

One thing is per-Ractor rather than per-fiber: `Hibiki.error_handler`, the only configuration Hibiki has. Set it once in an initializer, and every thread in that Ractor sees it, threads spawned later included. [Error handling layers]({% link _ref_rails/error-handling-layers.md %}#layer-2-hibikierror_handler-for-errors-in-effects) gives a Rails initializer example.
{: .note }

## TL;DR

- **Threads** each get their own bookkeeping, and a graph should live on one thread. Send messages to it from the others.
- **Fibers** inherit the tracking window and the owner, so reads inside enumerators and async tasks still count. They never inherit an open batch.
- **Ractors** each run an independent reactive world, with their own error handler.
