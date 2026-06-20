# ADHTML client runtime

The hand-written, **dependency-free** JavaScript runtime that interprets ADHTML's hydration wire format
(RFC-0003 / ADR-0006). It is the *entire* upfront client JS for an interactive page — the static
perimeter ships **zero** JS; only islands load this.

- **Size**: **≈ 2.2 KiB gzipped** (≈ 5.0 KB raw) — well under the ≤ 4 KiB hard budget (`build.js` gates it).
- **Zero runtime dependencies, no Swift→WASM** (ADR-0006): a hydration runtime is DOM-bound glue,
  WASM's weakest axis. It is authored in **plain JavaScript with JSDoc types** (type-checked via
  `tsc --checkJs`, no transpile step) and built with bun's built-in bundler. (Dev-dependencies —
  `@happy-dom/global-registrator`, `@playwright/test`, `typescript`, `@types/bun` — are used by
  tests/typecheck only, never bundled.)
- **Fast native APIs over abstraction**: the document-level delegated listener resolves a click with
  `Element.closest()` (one native ancestor-walk, no `composedPath()` array per event); `morph` reuses a
  single `<template>` and patches attributes over the live `NamedNodeMap` without snapshot allocations.
- **Versioned**: `WIRE_VERSION` must equal `ADHTMLCore.wireFormatVersion` (= 1); `parseState` rejects a
  mismatch, and a test asserts parity.

## Layout

| File | Role | Tested |
|---|---|---|
| `src/signals.js` | Fine-grained push-pull signals + effects (batched, deduped scheduler) | ✅ bun |
| `src/wire.js` | Parse the inline `application/adh-state+json` state into signals | ✅ bun |
| `src/behaviors.js` | The closed behavior registry (`increment`/`toggle`/`set`) — mirrors Swift `Behavior` | ✅ bun |
| `src/expr.js` | Iterative evaluator for the closed client-recomputable expression set (mirrors Swift `WireExpr`) | ✅ bun |
| `src/morph.js` | Lean id-aware DOM morph for SSE `morph` out-of-band swaps | ✅ happy-dom |
| `src/runtime.js` | DOM layer: delegated listener (`closest()`), `data-adh-bind:*` bindings, load directives (incl. `IntersectionObserver`), SSE `connect`, `hydrate()` entry | ✅ happy-dom + chromium |
| `build.js` | `Bun.build` minify → `adh-runtime.min.js` + gzip ≤ 4 KiB gate | — |

## Commands

```sh
cd ClientRuntime
bun install         # dev/test deps (happy-dom, playwright, typescript) — not bundled
bun run typecheck   # tsc --noEmit --checkJs over the JSDoc-typed src/ (strict)
bun test            # DOM-free core (signals/wire/behaviors/expr) + DOM layer under happy-dom
bun run build       # minify + size-gate -> adh-runtime.min.js (committed, SRI-pinned)
bun run e2e         # real-browser smoke + perf (Playwright/chromium)
bun run bench       # hot-path microbenchmarks (happy-dom; min over runs)
```

## How it works

1. `hydrate()` reads `<script type="application/adh-state+json" id="adh-state">` and reconstructs the
   cells as signals (positional: array index == the ref used by bindings/scope).
2. For each island (`data-adh-id`), it honors the `data-adh-on` loading contract: `load` (now),
   `idle` (`requestIdleCallback`), `visible` (`IntersectionObserver`, lazy until it scrolls in — with
   an immediate fallback when the API is absent), `media:(…)` (`matchMedia`) — then wires it.
3. Wiring = one delegated listener **per event type for the whole document** (qwikloader-style). On an
   event, `closest('[data-adh-on:<type>]')` finds the nearest handler element in one native call; if its
   island has wired, the behavior (`<name>#<cell>[#param]`) runs. Plus `data-adh-bind:text|value|class`
   effects that update the node when their signal changes.
4. `connect(url, state)` subscribes to an SSE endpoint and applies live updates: `patch` events set
   cells (fine-grained), `morph` events reconcile an island's subtree to new server HTML (preserving
   focus/state by id, via `morph.js`). Requires ADServe SSE support
   (`docs/integration/adserve-requirements.md`).

## Testing

- `bun run test` — DOM-free core (signals/wire/behaviors/expr) + the DOM layer under happy-dom.
- `bun run e2e` — real-browser (Playwright/chromium) over `e2e/server.js`: real-layout
  `IntersectionObserver` (the `visible` directive), real event timing, and a `/perf` route that times
  bulk `hydrate()` + delegated-click interaction latency in native DOM (the honest numbers; happy-dom
  overstates absolute timings).
- `bun run typecheck` / `bun run build` — strict `tsc --checkJs`; minify + the gzip-budget gate.

## Benchmarks

Optional, **not part of CI**. The cross-framework tools require internet (pull production builds from
esm.sh / unpkg) and chromium (`bunx playwright install chromium`).

- `bun run bench` — happy-dom hot-path microbenchmarks (signals fan-out, morph, hydrate). happy-dom is a
  JS DOM (~100× slower than a browser), so use it for *relative* deltas, not absolute numbers.
- `bun run bench:compare` — same-machine, same-workload comparison (500 SSR counters → make interactive →
  2000 clicks) of ADHTML vs Vanilla, React, Vue, Preact, Alpine, petite-vue in **real chromium**. Reports
  time-to-interactive + per-interaction latency. Every runtime is measured under the same machine load,
  so the ranking is load-independent.
- `bun run bench:size` — real gzipped runtime size of each framework's production bundle (same gzip method
  as `build.js`).

Representative result (chromium, 500 counters, min of 3): ADHTML is second only to hand-rolled vanilla on
both time-to-interactive (**1.9 ms** vs ~5.3–5.5 ms for React/Vue/Preact) and interaction latency
(**4.35 µs/click**), and is the smallest runtime measured (**2.2 KB** gzip vs 6.2 KB Preact, 37.5 KB Vue,
46.8 KB React). Caveat: a counter workload favors fine-grained/island models; the TTI win is structural,
the interaction gap narrows for large dynamic subtrees (which ADHTML updates via server-driven SSE `morph`).

## Known gaps (follow-ups)

- **id-set morph reordering** preserves keyed nodes across sibling reorders (`morph.js`); full
  idiomorph-style cross-parent keyed moves are still a follow-up.
- **Client computed recomputation** is implemented for the closed `Reactive` expression set (`expr.js`);
  an opaque Swift `computed { … }` closure still has no client formula (SSE-`patch` updated).
- The served artifact's **Subresource-Integrity** hash is computed Swift-side (`ADHTMLSRI`, swift-crypto).
