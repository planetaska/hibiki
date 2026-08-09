# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-08-09

### Added

- **`equals:` — a per-signal equality override** on `State` and `Derived`, and
  passed through by the `state`/`derived` helpers in `Hibiki::DSL` and
  `Hibiki::Reactive`. Solid's `createSignal(value, { equals })` shape:
  omitted/`nil` keeps `==`; a callable is a custom comparator, called with
  `(prev, next)`, truthy meaning "unchanged"; `equals: false` means every write
  notifies. The override is honored at both places equality guards the graph —
  the write gate (`State#value=`) and the effect equality gate at the batch
  flush (new `Trackable#changed_from?`, consulted by
  `Observer#sources_changed?`). Signals that don't pass `equals:` behave
  exactly as before.

## [0.2.0] - 2026-07-29

### Changed

- **BREAKING: effects re-run only when a value they read actually changed.**
  Every read now remembers the value it saw, and at the batch flush an effect
  compares each of its dependencies against what it last read; if everything
  compares `==`, the effect does not run and its scheduler is not called.
  Svelte's `$derived` compares, and now so does Hibiki — on the reading side,
  because a derived has already notified its subscribers by the time it knows
  its new value. Measured motivation: a write that rippled through a derived to
  a structurally identical value pushed a 159 KB re-render with nothing
  changed anywhere.

  Two behaviour changes to be aware of:

  - an effect kept for a side effect *per write* (a heartbeat, a log line, a
    counter) must read the value that genuinely changes rather than a derived
    summary that often doesn't;
  - a derived that returns the same object it mutated compares equal to itself,
    so the gate swallows the update — return a new object. `Effect#run` still
    bypasses the gate entirely.

  A batch that nets to no change (`batch { a.value = 2; a.value = 1 }`) also
  stops re-running effects. `Derived`'s laziness is unchanged: it still
  recomputes on read, never on write.

## [0.1.0] - 2026-07-18

### Added

- Initial signal core: `Hibiki::State` (writable signal), `Hibiki::Derived`
  (lazy computed signal with runtime dependency tracking), `Hibiki::Effect`
  (eager side effects).
- Opt-in `Hibiki::DSL` providing bare `state` / `derived` / `effect` helpers.
