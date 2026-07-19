---
title: Fragment-level render effects
nav_order: 4
---

# Fragment-level render effects (a future direction)

Status: designed, deliberately deferred. This page records the idea so the
design isn't re-derived from scratch when a page finally needs it. It
concerns the glue gems
([hibiki_rails](https://github.com/planetaska/hibiki-rails),
[hibiki_phlex](https://github.com/planetaska/hibiki-phlex)), not the
signal core.

## The tax today: one renderable unit per fragment

If you want fine-grained updates over the wire — a write to `step`
re-sending only the step markup — every independently-updatable region of
a page needs its own renderable unit:

- In the ERB style (`hibiki_rails`), that's **one partial per fragment**:
  each effect broadcasts `partial: "counter/count"` or
  `partial: "counter/step"`, and the initial page render reuses the same
  partials as placeholders.
- In the Phlex style (`hibiki_phlex`), that's **one component class per
  fragment**: `Hibiki::Phlex.render_effect` is component-grained by
  design — the effect's first run is the dependency-collecting render of
  the *whole* `view_template`, so every signal read anywhere in the
  component subscribes that one effect. The only way to get a smaller
  update unit is to make the fragment *be* a component with its own
  `render_effect`.

This is forced, not incidental. Three constraints intersect:

1. **Update granularity ≡ template granularity.** The wire protocol is
   fragment replacement keyed on the transmitted HTML's root DOM id. If
   the server should be able to send *just* the step markup, something on
   the server must be able to render *just* the step markup.
2. **The same markup renders in two contexts** — the initial page paint
   and every subsequent broadcast — so it must live in one shared,
   addressable place.
3. **The template system's unit of composition** is a file (ERB) or a
   class (Phlex). Whatever "one renderable unit" means, it means one of
   those.

It's the same tax every turbo-rails app pays in partials; hibiki didn't
add it. But Phlex opens a door ERB can't: a class can have methods.

## The idea: push the effect boundary inside the component

One class owns the page section; each independently-updatable region is a
private method; each method is wrapped in its **own** effect:

```ruby
class Counter::Show < Phlex::HTML
  def view_template
    div(...) do
      reactive_fragment :count_display   # own effect
      reactive_fragment :step_display    # own effect
      controls                           # static, no effect
    end
  end

  private

  def count_display = p(id: "count") { "count: #{@count.value} · doubled: #{@doubled.value}" }
  def step_display  = p(id: "step")  { "step: #{@step.value}" }
end
```

(`reactive_fragment` is a sketch name, not a commitment — the real API
falls out of the first page that needs it.)

The first full render runs each fragment method inside its effect's first
run, so the signals read in `count_display` subscribe *that* effect only.
Afterward, writing `step` re-runs only `step_display` — re-rendering just
that method's markup on the same instance and handing just that fragment's
HTML to the transport block. Per-fragment display classes (or partials, in
ERB terms) collapse into methods of one class.

The precedent is Solid's compiled JSX: the template renders once, and each
dynamic "hole" becomes its own nested effect. This is that idea at
fragment granularity instead of text-node granularity.

## Why the machinery is already shaped for it

- **The owner tree.** Hibiki's ownership model (Solid's Owner) already
  supports effects nested under a parent scope: a channel's root would own
  the component's fragment effects, and disposing the graph disposes all
  of them with zero new lifecycle code.
- **The wire protocol doesn't change.** The client keys replacement on the
  transmitted HTML's root DOM id — it can't tell whether a fragment came
  from a dedicated component, a partial, or a method. No client changes.
- **The scheduler seam composes per effect.** `scheduler:` passes through
  to each fragment's effect, so per-fragment debouncing works for free.

## Why it's deferred

1. **Isolated fragment re-render on a live Phlex instance.**
   `Hibiki::Phlex::Rerenderable` already reaches into Phlex's private
   rendering state to re-render a whole component; rendering *one method*
   in isolation — its own buffer, correct escaping context, same
   instance — reaches deeper still. Phlex 2's selective-rendering
   facility may be a substrate, but building on it deepens the already
   strict Phlex version pin and expands what the contract spec must guard.
2. **Tracking hygiene in the outer render.** During the initial full
   render, the outer pass must *not* subscribe to signals read inside
   fragments — otherwise a fragment write re-runs the whole component and
   nothing is gained. The core has the right primitive (nested observers
   own their reads), but the initial-render pass — outer render
   untracked, inner effects tracked — is exactly the kind of
   tracking-core subtlety this project changes slowly and with specs.
3. **No page has needed it.** A counter with two fragments shrugs off two
   small display classes. The tax only hurts on a page with many
   independently-updating regions — and that page is also what settles
   the API question (explicit `reactive_fragment` vs. something more
   automatic) with a concrete use case instead of speculation.

Until then, the workaround is cheap and boring: one small component (or
partial) per fragment, one `render_effect` each.
