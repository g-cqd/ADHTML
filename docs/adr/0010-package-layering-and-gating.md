# ADR 0010 — Package layering & dependency gating

- **Status**: Proposed
- **Date**: 2026-06-19
- **Related**: RFC-0001; ADR-0011 (reuse), ADR-0012 (NIO). Mirrors the `ADJSON` manifest

## Context

The package must keep a lean default graph (so consumers resolve almost nothing), isolate heavy/host
deps, stay Foundation-free in the core, and pin a deployment floor consistent with the `AD*` family.

## Decision

Mirror `ADJSON`'s manifest exactly:

- **Products**: `ADHTMLCore` (Foundation-free engine) + `ADHTML` (umbrella) + `.macro ADHTMLMacros`.
  Default core deps: `OrderedCollections` (deterministic attributes) + `ADFCore`. The macro target adds
  swift-syntax (603.0.0+).
- **Gated** (env-flag, appended only when set, so default resolution never fetches them):
  `ADHTMLServe` (`ADHTML_SERVE`, legacy alias `ADHTML_NIO`; formerly named `ADHTMLNIO` — a misnomer,
  it imports no NIO: the ADServe response bridge; pulls `ADJSON` for the wire too),
  `ADHTMLMarkdown` (`ADHTML_MARKDOWN`: swift-markdown, a C dep, with our own HTML renderer),
  `ADHTMLSRI` (`ADHTML_SRI`: swift-crypto SHA-256 — for Subresource Integrity **only**),
  `ADHTMLObservability` (`ADHTML_OBS`: swift-log/metrics/distributed-tracing — most speculative),
  `ADHTMLFuzz` (`ADHTML_FUZZ`: libFuzzer, Linux), and dev tooling (`ADHTML_DEV`: ADBuildTools
  lint/format, swift-docc-plugin, ordo-one/benchmark).
- **Settings**: `.swiftLanguageMode(.v6)`, `treatAllWarnings(as:.error)`, upcoming features
  `ExistentialAny`/`InferIsolatedConformances`/`InternalImportsByDefault`/`MemberImportVisibility`;
  the 100 ms `-warn-long-function-bodies`/`-warn-long-expression-type-checking` flags **only on
  internal targets** (they would block version-based resolution on a library).
- **Floor**: macOS 15 / iOS 18 / tvOS 18 / watchOS 11 / visionOS 2 — pinned by stdlib
  `Synchronization.Mutex`. **Adopt `Span`** (it back-deploys further). **Do not adopt** `InlineArray`
  / `UTF8Span` (macOS 26 / 2025 SDK — would raise the floor or fragment with `@available` shims).
  Verified against Apple docs.
- **Reject** `swift-foundation` (keep the core Foundation-free) and `swift-atomics` (redundant at the
  `Mutex` floor; keep only as a hypothetical WASM/legacy fallback).
- Deps resolve from a local checkout via `<DEP>_PATH` else published git (the family pattern).
  `Package.resolved` is gitignored (library convention).

## Consequences

- **Positive**: consumers of `ADHTML`/`ADHTMLCore` resolve only OrderedCollections + ADFCore (+
  swift-syntax for the macro); everything heavy is opt-in; the core stays portable/Embedded-amenable;
  family-consistent.
- **Negative**: a larger manifest with several gates — but each gate is justified and zero-cost when
  off; matches the proven `ADJSON` shape so maintenance is familiar.
