# ADR 0017 — Class-merge & conditional-render wire (P2 / P6)

- **Status**: Accepted (implemented 2026-06-20)
- **Date**: 2026-06-20
- **Related**: RFC-0021 (P2 class-merge, P6 conditional); ADR-0005/0007 (bindings as `data-adh-*`, the
  cell-ref convention); ADR-0006 (the ≤ 4 KiB JS budget). Mirrors the closed-set + parity discipline of
  ADR-0009's `Behavior` / `Action`.

## Context

The prototype parity gap (RFC-0021 §1) needs three everyday interactions the engine could not yet express
declaratively: toggling a CSS class on state (S1 sidebar, L2 density, S2 active, T2 popover-open),
conditionally **mounting** content (T2/T6/T7 popover/add-row/hints, D4 loading, S3 clear-button), and
conditionally **showing** content. The existing `bind(.class, to:)` sets `className` wholesale, which
clobbers static classes — unusable for "add one class to an element that already has three".

## Decision

Add three closed `data-adh-*` directives, each a single signal effect on the client, escape-by-default,
each with a no-JS fallback. All reuse the existing raw-cell-id ref convention (`bind`/`on`), so one index
scheme spans every directive; the runtime interprets them in `bindDirectives` (one pass in `wireIsland`).

- **P2 — `.classToggle(name, when:)` → `data-adh-class="name:cell;name2:cell2"`.** The runtime
  `classList.toggle(name, !!cell)` — a **merge**, never touching the rest of `className`. Repeated toggles
  coalesce into one attribute (`AttributeStore` learns to `;`-merge `data-adh-class`, like `style`). The
  name may itself contain `:` (Tailwind variants like `hover:bg-blue`), so the client splits each pair on
  its **last** `:`. The typed (`Signal`/`Computed`/`Reactive`) overloads also paint the class into the
  initial server `class` when the cell is initially on — no hydration flash.
- **P6 — `When($c) { … }` → `<template data-adh-if="cell">…</template>`.** Mount/unmount: the runtime
  clones the template's content in after it when the cell is truthy and removes it when falsy (the
  `v-if`/`x-if` model). Because the content lives in an inert `<template>`, it is **absent without JS** —
  the correct fallback for on-demand reveals (popover/spinner/hint/clear-button, all initially closed).
- **P6 — `.show(when: $c)` → `data-adh-show="cell"`.** The runtime toggles `display`; the node **stays in
  the DOM**. The typed overloads stamp the initial inline `display:none` when the cell is initially off,
  so it is hidden without JS and never flashes. This is the tool for "exists without JS, toggles
  visibility" — the complement to `When`'s mount/unmount.

## Consequences

- **Positive.** The toggle/visibility papercuts close declaratively, in typed Swift, with a no-JS story
  for each. `classToggle` composes with hand-authored CSS (merge, not clobber). `When` vs `.show` gives
  the author the mount-vs-display choice the platform actually distinguishes. +216 B gzip (3.21 → 3.43
  KiB), within budget.
- **Negative / limits.** (a) `When` content is shipped in a `<template>`, so it is JS-gated by design —
  content that must exist without JS uses `.show` or plain rendering. (b) Reactive bindings inside a
  `When`'s mounted clone are not re-wired on mount (the clone enters the DOM after `wireIsland` ran);
  delegated *events* inside it still work (document-level), so interactive buttons are fine, but
  live-updating text inside a `When` is a known v1 gap. (c) The `Reactive` overloads need an ambient
  render context (a `@Component` body), exactly like `bind(_:to:Reactive)`; the `Signal`/`Computed`
  overloads work anywhere.
- **Invariants kept.** Closed token set (no `eval`); Swift↔JS parity (happy-dom round-trips the exact
  emitted tokens); escape-by-default (`When` content escapes inside the template — XSS test); raw-cell-id
  ref convention unchanged; budget gated.
