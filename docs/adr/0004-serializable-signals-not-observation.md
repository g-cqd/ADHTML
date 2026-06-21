# ADR 0004 — Custom serializable signals (not Swift `Observation`)

- **Status**: Proposed
- **Date**: 2026-06-19
- **Related**: RFC-0003; ADR-0005 (islands), ADR-0007 (wire format)

## Context

The reactivity model must (a) be evaluable on the server for the initial render, (b) **serialize to a
wire format** so the client can resume it, and (c) drive fine-grained DOM updates (not a virtual DOM).
Swift's `Observation`/`@Observable` (macOS 14 / iOS 17, available at our floor) is the native reactive
primitive — but it tracks property *access* at runtime to invalidate SwiftUI views; it is **not
serializable** and not designed to linearize a value graph to JSON. Using it would not yield a wire
payload. (Verified against Apple's `Observation` docs.)

## Decision

Implement a custom **serializable signal graph**: `Signal<Value>` (a reactive cell) and
`Computed<Value>` (a derived cell capturing dependency `CellID`s). Cells are `Sendable` value types with a
`CellID` that is, in **Phase 1, the cell's creation index** within its arena (deterministic across identical
renders — enough for serialization). A later refinement derives it from the render-scope path via
`ADFCore.XXH64`, giving stability under structural reordering — required only once SSE morph/patch targets
cells *across* renders (until then, cross-render patching holds for byte-identical re-renders). The graph is
server-evaluated for the initial HTML and **linearized to the wire format** (ADR-0007), where cells keep
their creation index so the inline state stays aligned with the DOM's cell refs. Client updates are
fine-grained (Solid/Svelte-5 model): only DOM nodes bound to a changed cell update.

Document the divergence from native `Observation` honestly: we deliberately do **not** leverage it
here because it cannot serialize — a justified "lack of native-API leverage" the prism asks us to
surface.

## Consequences

- **Positive**: one reactive model spans server render and client resume; wire-serializable by design;
  fine-grained updates; stable IDs enable SSE patching.
- **Negative**: a bespoke reactive system to build and test (vs reusing `Observation`); mitigated by a
  small, closed surface (`Signal`/`Computed` + the closed `Behavior` enum, RFC-0004) and property
  tests on the graph linearization. Revisit if a future `Observation` gains serialization.
