# Why no transparent signals?

Two designs that would hide `.value` were tried and rejected. Each hits a rule of the Ruby language no library can bend, and each fails silently by taking the wrong branch. Do not propose either, and do not relitigate the decision.

| Design | Where it breaks | Why |
|---|---|---|
| A `BasicObject` wrapper forwarding `method_missing` to `@signal.value` | `if wrapper` | truthiness is not a method: a wrapper is never `nil` or `false`, so `if flag` is always true, and `flag ? a : b` (the case fine-grained reactivity exists for) takes the wrong branch. `==`, `equal?`, `nil == x` and `case`/`===` misbehave too |
| A `reactive do ... end` block where bare locals are signals | `count = 1` | the parser marks `count` a local at the first assignment; from then on a bare `count` is a variable lookup, not a method call, and nothing can intercept it |

Svelte 5 has transparent reads because its compiler rewrites `count` into `$.get(count)` at build time. Ruby has no build step, so a runtime trick is the only route, and truthiness closes it.

The one transparency that works is at the point of use. `Hibiki::Reactive` defines ordinary reader and writer methods with `define_method`, so:

- `count` returns the real Integer, and `if`, `==`, and `case` all work;
- writes are `self.count = 1`, a real method call the writer can see;
- inheritance and testing come for free, because it is a plain class.

See `class-based-reactivity.md` for the macros.

## TL;DR

- Transparency at the point of use: achievable, shipped as `Hibiki::Reactive`.
- Transparency of the value object: fails on truthiness.
- Transparency of bare assignment: fails on the parser.
- Both failures are silent wrong-branch bugs, so both designs are rejected.

Full docs: https://planetaska.github.io/hibiki/why-no-transparent-signals/
