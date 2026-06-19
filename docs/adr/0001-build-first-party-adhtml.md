# ADR 0001 — Build a first-party ADHTML

- **Status**: Proposed
- **Date**: 2026-06-19
- **Related**: RFC-0001; supersedes spare-parts-app ADR-0044 (adopt Elementary) for this codebase

## Context

spare-parts-app ADR-0044 adopted Elementary behind a `ViewRenderer` port and explicitly deferred a
first-party engine "unless AD\*-family consistency or deep ADJSON/URLBuilder typing demands it; if so,
port Elementary's byte-writer + escape-by-default design." Two requirements now meet that bar:

1. **Reactive + hydratable output.** No Swift HTML library (Elementary, swift-html, Plot, HTMLKit,
   Ignite, swift-dom; Tokamak is client-only and archived) renders server-side *and* hydrates the same
   markup on the client. Elementary's interactivity is htmx (server round-trip); Ignite emits canned
   JS. The requirement in RFC-0001/0003 is genuinely unmet by adoption.
2. **Deep AD\* typing.** Wire-state serialization is `ADJSON`; island/cache IDs + escaping ride
   `ADFCore`; the byte sink + asset safety ride `ADServe`. A first-party engine shares these instead of
   re-implementing them (ADR-0011).

## Decision

Build **ADHTML** as a first-party `AD*` package, **porting Elementary's proven foundations** — the
struct + phantom-`Tag` element model with zero `any`, escape-by-default, the byte-streaming writer
shape, and `consuming`/`Sendable` rigor — and going beyond on the three axes Elementary does not
cover: an iterative non-recursive renderer (ADR-0002), context-aware escaping (ADR-0003), and a
reactivity/hydration layer (RFC-0003). ADR-0044's "adopt Elementary" stance is superseded here.

## Consequences

- **Positive**: AD\*-coherent (one family idiom, shared primitives, no second escaping/byte stack);
  unlocks the reactive/hydratable surface no Swift lib offers; full control of the render path for the
  performance and security prisms.
- **Negative**: more code to own and test than adopting a dependency; pre-1.0 churn is ours. Mitigated
  by porting Elementary's settled design rather than inventing, and by the test/fuzz/benchmark gates.
- Elementary remains the reference and a fallback behind the same `ViewRenderer` port if ever needed.
