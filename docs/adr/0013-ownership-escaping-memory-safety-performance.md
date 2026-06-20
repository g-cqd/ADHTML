# ADR 0013 — Ownership, escaping & memory-safety performance

- **Status**: Accepted (implemented 2026-06-20)
- **Date**: 2026-06-20
- **Related**: RFC-0002, RFC-0003; ADR-0002 (iterative renderer), ADR-0003 (escaping), ADR-0011 (ADJSON/
  ADFCore reuse). SE-0377 (ownership); SE-0447/0456/0464/0467/0485/0524 (Span/OutputSpan/UTF8Span)

## Context

A no-new-features hardening pass over the Swift engine and the JS runtime, against the project prism:
bypass the Copy-on-Write tax, raise type/concurrency/memory safety, make hot paths failure-safe, conform
to standards, and remove the remaining data-driven recursions. Measurement-gated: a network-free release
probe (`ADHTMLPerfProbe`) for local wall-clock before/after, and the ordo-one suite (`mallocCountTotal`)
as the authoritative CI gate. Local wall-clock is load-sensitive; the structural wins below are
deterministic by construction and the numbers are from quiescent runs.

## Decision

1. **Consuming attribute modifiers (CoW bypass).** `HTMLElement.attribute` and every attribute/binding
   modifier (`class`/`id`/`href`/`src`/…/`on`/`bind`) are `consuming func … -> Self { var copy = consume
   self; … }`. A modifier chain on a dying temporary MOVES the element, so the `OrderedDictionary`
   attribute store is uniquely held and mutated in place — one allocation per chain, not a deep copy per
   link. Storing-then-modifying still copies (unchanged). *Measured: render/modifier-chain ≈ −25%.*

2. **Bulk-copy escaper.** `Escaper.writeEscaped` scans for runs of safe bytes and copies each run with a
   single bulk `write`, emitting an entity only at an escapable byte (the algorithm the file header
   already claimed — fixes a code/comment mismatch). Byte-identical output. *Measured: escape/prose
   (realistic) ≈ −39%; escape/text-heavy (~50% specials, pathological) ≈ +3% — real HTML is prose-like.*

3. **Reuse ADJSON's HTML-safe encoder for the state script (ADR-0011).** The inline state block is
   escaped by `JSONEncodingOptions(escapeHTMLUnsafe: true)` — ADJSON escapes `<`/`>`/`&` and
   U+2028/U+2029 to `\uXXXX` *during* its SWAR-accelerated encode. ADHTML's duplicate `escapeScriptJSON`
   and its separate second pass are deleted. The wire bytes still parse to the same JSON value.
   *Measured: render/reactive-island ≈ −6% (one fewer pass).*

4. **De-recurse `WireSerializer.json` + depth cap.** The last Swift data recursion (nested-array fold) is
   now an explicit-stack post-order walk (coherent with ADR-0002). A `maxValueDepth` (64) ceiling throws
   `WireError` instead of risking a deep walk (failure-safe; the nesting is author-bounded).

5. **Typed `StateKey` (allocation hygiene).** `CellArena.stateCell` keys its dedup map by a `struct
   StateKey { scope, key }` instead of a `"\(scope).\(key)"` interpolation — no per-`@State`-read heap
   allocation. Wall-clock-neutral at this scale; reflected by `mallocCountTotal` in CI.

6. **JS failure-safe + de-recursion.** Every `JSON.parse` degrades instead of throwing (malformed inline
   state → static page; malformed SSE frame → dropped; per-island wiring isolated; `set` never assigns
   NaN). `morph` is now an iterative worklist (no DOM-subtree recursion). 1.73 KiB gzip (≤ 6 KiB).

## Consequences

- **Positive:** fewer allocations and copies on the hot paths; one fewer escaping pass and one fewer
  duplicated escaper (DRY); both data recursions removed (stack-safe everywhere); the runtime degrades
  gracefully under malformed input.
- **Tradeoff — consuming ABI:** borrowing→`consuming` changes the calling convention, so an *incremental*
  build can mislink the macro test bundle (observed SIGTRAP); a clean build fixes it. CI builds clean;
  noted in CONTRIBUTING.
- **Tradeoff — escaper on pathological input:** ~3% slower only on ~50%-special-char text (not real HTML).
- **Failure-safe ceilings:** the wire depth cap rejects absurd nesting (a deliberate, generous limit).

## Rejected / deferred (coherency & prudence)

- **`@dynamicMemberLookup` for attributes — rejected.** Would trade compile-time attribute legality
  (ADR-0009, the thesis) for stringly-typed access. The trait-gated modifiers are the correct surface.
- **De-recursing the *lowering* walk — rejected.** Lowering recurses through the monomorphized *type*
  tree; an iterative version needs an `[any HTML]` work stack, breaking the zero-`any` tenet (RFC-0002).
  It is source-bounded (large collections lower via the flat `_HTMLArray` loop), and the data-driven
  render walk — the actual stack-safety guarantee (ADR-0002, `maxDepth`) — is already iterative.
- **Eliminating the `WireValue → JSONValue` bridge — rejected.** Would duplicate JSON encoding ADJSON
  owns (ADR-0011). De-recursion (4) meets the prism without duplication.
- **Promoting `SWAR` to `ADFCore` for the entity escaper — deferred.** `SWAR` (currently internal to
  ADJSONCore, which already depends on ADFCore) is a foundation primitive whose proper home is ADFCore;
  promoting it would let the HTML entity escaper scan 8 bytes/step. Deferred because the escaper is **not**
  the bottleneck (prose ≈ 5 µs vs wide-list ≈ 175 µs) and word-loads would widen the unsafe surface
  against the memory-safety prism. Follow-up: promote `SWAR` to ADFCore and have ADJSON adopt it (removing
  the cross-repo duplicate) before SWAR-accelerating the entity escaper.
- **`borrowing _render` — deferred.** A protocol-wide ownership change for an uncertain sub-few-percent
  gain on a non-DSL path; the clear DSL CoW win is captured by (1).

## "Identify" findings (this pass)

- **Bugs fixed:** escaper code/comment mismatch (1/2); a latent `$0`-shadow in the wide-list benchmark
  (never compiled offline).
- **Duplication removed:** `escapeScriptJSON` (now ADJSON's `escapeHTMLUnsafe`).
- **Recursion removed:** `WireSerializer.json` (Swift), `morph` (JS).
- **Native leverage:** ADJSON `escapeHTMLUnsafe`; SWAR-in-ADFCore noted as a follow-up.
- **Unused/unwired:** `ADHTMLMarkdown`/`Observability`/`NIO` remain gated placeholders (expected — the NIO
  bridge awaits the ADServe surface). No dead or unreachable shipped code found.

## Tooling

`Sources/ADHTMLPerfProbe` (network-free release wall-clock probe over ADHTMLCore, no DEV deps) and two new
ordo-one benches (`render/modifier-chain`, `render/reactive-island`). Committing ordo-one threshold
baselines (`Thresholds/`) is a follow-up — they must be captured from a CI run (the DEV bench deps don't
resolve offline); the bench job already publishes results to the job summary.
