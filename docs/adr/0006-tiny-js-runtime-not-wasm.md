# ADR 0006 — Tiny hand-written JS runtime (reject Swift→WASM baseline)

- **Status**: Accepted (implemented 2026-06-20)
- **Date**: 2026-06-19
- **Related**: RFC-0003; ADR-0005 (islands), ADR-0007 (wire format), ADR-0011 (SRI via swift-crypto)
- **Implementation**: hand-written TypeScript (signals, wire parse, closed behavior registry, DOM layer
  with delegated events, bindings, Astro load directives incl. `IntersectionObserver`, SSE `patch` +
  `morph`), built with bun → **1.64 KiB gzip** (≤ 6 KiB hard gate). 13 tests (DOM-free core + happy-dom
  DOM layer); strict `tsc` typecheck. Full idiomorph-style reordering remains a follow-up.

## Context

Islands need a client runtime to interpret the wire format (resume listeners, run signals, bind the
DOM, apply SSE patches). Two options: compile Swift→WASM (SwiftWasm/JavaScriptKit/Tokamak) or
hand-write a tiny JS runtime. A hydration runtime is, by nature, DOM-bound glue — WASM's weakest axis.

Measured (2026): standard SwiftWasm hello-world is multi-MB; Embedded Swift reaches sub-400 KB only by
dropping `String`/reflection; every DOM op crosses the JS↔WASM boundary; `Tokamak` is archived (Jan
2026) and `carton` deprecated. A hand-written reactive JS runtime is single-digit KB (qwikloader ≈ 1
KB, Datastar ≈ 10–15 KB) with zero boundary cost and parses+executes in < 5 ms.

## Decision

Ship a **hand-written generic JS runtime, target ≈ 2–6 KB gzipped** — a delegated-listener loader
(qwikloader-style) + a fine-grained signals core + declarative DOM binding + an SSE morph/patch client
— served **once** as a static, **SRI-hashed** asset (SHA-256 via swift-crypto, gated `ADHTML_SRI`,
ADR-0011). It is versioned to match the wire format (`"v"`). **Reject Swift→WASM** as the baseline
runtime. WASM is allowed only as an **opt-in heavy-compute island** escape hatch where boundary cost
is amortized over real work.

## Consequences

- **Positive**: smallest possible baseline JS; fast cold-start/TTI; native DOM access (no boundary
  tax); debuggable in any browser; trivially cacheable + integrity-pinned. Swift stays on the server
  where it is unconstrained.
- **Negative**: a (small) hand-written JS artifact to maintain and test outside the Swift
  type-checker (RFC-0004 §4 names this as part of the ~2% non-checked surface) — covered by browser
  smoke tests and a hard ≤ 6 KB CI size gate. A build/minify step (esbuild) is dev-gated; the minified
  output is committed and SRI-pinned so consumers need no Node.
