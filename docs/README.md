# ADHTML design corpus

This directory is the decision record for ADHTML — a reactive, hydratable, Swift-only server-side
rendering engine. **RFCs** capture umbrella designs and the novel subsystem; **ADRs** capture the
discrete, independently-revisable decisions. Numbering is ADHTML's own series, from `0001`.

ADRs are immutable once accepted: supersede with a new ADR rather than editing an old one.

## RFCs

| # | Title | Status |
|---|---|---|
| [0001](rfcs/0001-adhtml-reactive-hydratable-ssr-engine.md) | ADHTML: a reactive, hydratable Swift SSR engine (umbrella) | Proposed |
| [0002](rfcs/0002-iterative-rendering-core-and-byte-sink.md) | The iterative rendering core & byte-sink contract | Proposed |
| [0003](rfcs/0003-reactivity-hydration-and-wire-format.md) | Reactivity, hydration & the wire format | Proposed |
| [0004](rfcs/0004-whole-scope-compile-time-checked-ssr.md) | Whole-scope compile-time-checked SSR (Swift-only, no templates) | Proposed |

## ADRs

| # | Title | Status |
|---|---|---|
| [0001](adr/0001-build-first-party-adhtml.md) | Build a first-party `ADHTML` (supersede ADR-0044's "adopt Elementary") | Proposed |
| [0002](adr/0002-iterative-non-recursive-renderer.md) | Iterative, non-recursive renderer (opcode program) | Proposed |
| [0003](adr/0003-escape-by-default-context-aware.md) | Escape-by-default + context-aware escaping | Proposed |
| [0004](adr/0004-serializable-signals-not-observation.md) | Custom serializable signals (not Swift `Observation`) | Proposed |
| [0005](adr/0005-islands-resumable-wiring.md) | Islands + resumable wiring (reject full & whole-page hydration) | Proposed |
| [0006](adr/0006-tiny-js-runtime-not-wasm.md) | Tiny hand-written JS runtime (reject Swift→WASM baseline) | Proposed |
| [0007](adr/0007-wire-format-v1.md) | Wire format v1 (versioned, index-deduped, ADJSON-serialized) | Proposed |
| [0008](adr/0008-lean-macro-surface.md) | Lean macro surface (`@Component`, `#html`, `#attr`) | Proposed |
| [0009](adr/0009-swift-only-no-templates.md) | Swift-only views: no template files; whole-scope compile-time type-checking | Proposed |
| [0010](adr/0010-package-layering-and-gating.md) | Package layering & dependency gating (mirror ADJSON) | Proposed |
| [0011](adr/0011-adfcore-adjson-adserve-reuse.md) | `ADFCore`/`ADJSON`/`ADServeCore` reuse policy (no duplication) | Proposed |
| [0012](adr/0012-adserve-integration.md) | ADServe integration & the streaming dependency | Proposed |

## Reading order

1. **RFC-0001** for the vision, the state-of-the-art survey, and the architecture map.
2. **RFC-0002** (rendering) and **RFC-0003** (reactivity/hydration) for the two halves of the engine.
3. **RFC-0004** for the Swift-only / whole-scope-compile thesis.
4. The ADRs for the specific forks each subsystem took.

## Provenance

ADHTML realizes the first-party `ADHtml` that spare-parts-app **ADR-0044** deferred, within the
SSR/hypermedia direction set by spare-parts-app **RFC-0018** and the ADServe view-support work of
**ADR-0046**. The design is grounded in four research passes (JS-framework SSR/hydration SOTA; Swift
HTML DSLs; leverageable Apple/swiftlang/swift-server packages; an architecture review) and verified
against Apple's documentation for the load-bearing APIs (`Synchronization.Mutex`, `Span`,
`InlineArray`, `Observation`).
