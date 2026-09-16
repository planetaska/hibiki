# Threading model

Hibiki keeps three facts about the flow of execution that is running right now, all in fiber storage: the tracking window (which derived or effect is computing), the current owner (which effect or root adopts new effects), and the open batch (depth plus the queue of waiting effects). The signals themselves are ordinary objects with no lock inside. Private bookkeeping plus unlocked objects is the whole design.

## Where each fact lives, and why

| Fact | Storage | Inherited by a new fiber? | Why |
|---|---|---|---|
| tracking window | `Fiber[:hibiki_observer]` | yes | a read inside an `Enumerator#next` fiber or an async task still registers its edge; the worst case is one extra subscription |
| current owner | `Fiber[:hibiki_owner]` | yes | same reason |
| batch depth and queue | `Thread.current[]` (fiber-local despite the name) | no | a fiber spawned mid-batch would inherit a depth it can never unwind, and its effects would wait on a flush that never comes |
| `Hibiki.error_handler` | `Ractor.current[]` | per Ractor, every thread sees it | configuration set once in an initializer must reach threads spawned later |

Do not unify the two fiber pockets; each choice fixes a real bug.

## Threads: one graph per thread

- A read on another thread never subscribes your running effect.
- An effect created on another thread is never adopted by yours.
- A batch defers only your own effects; a write on another thread runs its effects at once.
- A graph is safe on one thread and unsafe under two, because signals hold no locks. Give each graph a thread and send it messages.

```ruby
inbox = Queue.new
owner = Thread.new do
  count = state(0)
  effect { puts "count is #{count.value}" }
  while (message = inbox.pop)
    count.value = message
  end
end
inbox << 1   # from any thread; the effect runs on the owner thread
inbox.close
owner.join
```

hibiki_rails works this way: each action is posted to the graph's own thread and applied there inside one batch. Load `hibiki-rails` for the Rails side (Puma threads, job runners, after_commit pings).

## Fibers

- Tracking follows a read into an enumerator's internal fiber: `derived { Enumerator.new { |y| y << count.value * 2 }.next }` updates when `count` changes.
- A fiber started inside a batch is not batching: `Fiber.new { count.value = 1 }.resume` inside `batch { }` runs its effects at once.

## Ractors

- Each Ractor runs its own reactive world; hibiki keeps nothing in module-level variables, which is what would raise `IsolationError` off the main Ractor.
- Signals are unshareable; a signal handed to another Ractor is copied or refused, so a graph never straddles the boundary.
- `Hibiki.error_handler` is per Ractor, the only configuration hibiki has.

Full docs: https://planetaska.github.io/hibiki/threading-model/
