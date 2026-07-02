# ADR 0011 — `ADFCore` / `ADJSON` / `ADServeCore` reuse policy (no duplication)

- **Status**: Proposed
- **Date**: 2026-06-19
- **Related**: RFC-0002, RFC-0003; ADR-0003 (escaping), ADR-0007 (wire), ADR-0012 (ADServe), ADR-0013 (perf)
- **Implementation note**: `ADHTMLSRI` is implemented (gated `ADHTML_SRI`) — SHA-256 via swift-crypto
  confined to that one target; island/cache IDs still use `ADFCore.XXH64`. ADFCore ships no base64, so
  SRI carries a small standard-alphabet encoder. The inline state script now reuses ADJSON's HTML-safe
  JSON encoder (`escapeHTMLUnsafe`) instead of a duplicated escaper (ADR-0013). The `SWAR` byte-scan
  kernel now lives in `ADFCore` (public) — ADHTML's escaper uses it; ADJSON adopting it (to drop its
  internal copy) is a follow-up gated on import-visibility alignment in its `@inlinable` hot paths
  (ADR-0013). ADServeCore reuse remains pending the ADServe work.

## Context

The `AD*` family already ships the low-level primitives ADHTML needs. The prism flags *code
duplication* and *lack of leverage of existing packages* as defects. Re-implementing byte buffers,
hashing, UTF-8 handling, JSON serialization, or asset-path safety would be duplication.

## Decision

Build on the family, do not re-roll:

- **`ADFCore`** (ADFoundation): `ByteBufferPool` for the render output buffer; `XXH64` for island /
  component / cache IDs and weak ETags (non-crypto — correct for cache keys); `ASCII`, `PercentCoding`,
  `UTF8Validation`, `Hex` for the context-aware escapers (ADR-0003); checked arithmetic + BE/LE
  load/store if compact binary state is ever needed.
- **`ADJSON`**: serialize the hydration state graph (`WireEncodable` → bytes) and emit SSE signal
  patches via `ADJSONCore.JSONMergePatch` (RFC 7396) — no bespoke JSON writer or merge-patch (ADR-0007).
- **`ADServeCore`** (gated, via `ADHTMLServe`): `sha256HexLower` for SRI/strong ETags, `pathHasTraversal`
  for static-asset path safety, `ResponseContent`/`MediaType` for the response bridge (ADR-0012).

**Crypto rule**: a real cryptographic digest (swift-crypto SHA-256) is required **only** for
Subresource Integrity of the client runtime (a browser-enforced control); everything else (island IDs,
cache keys) uses the faster non-crypto `XXH64`.

## Consequences

- **Positive**: zero duplication; one battle-tested implementation per primitive; smaller surface to
  test/fuzz; family-consistent performance characteristics; the lean Foundation-free core is preserved
  (these deps are Foundation-free).
- **Negative**: a hard dependency on `ADFCore` in the core and (gated) on `ADJSON`/`ADServeCore`;
  acceptable — they are first-party, Foundation-free, and version-aligned. Confirm `ADJSONCore`'s
  Embedded-readiness before relying on it from an Embedded ADHTML build.
