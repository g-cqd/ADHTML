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
   NaN). `morph` is now an iterative worklist (no DOM-subtree recursion). ≈ 2.2 KiB gzip (≤ 4 KiB).

7. **JS authored in JavaScript + JSDoc; fastest native APIs.** The runtime is plain JS with JSDoc types
   (strict `tsc --checkJs`, no transpile) rather than TypeScript — perf-identical output, authored to
   reach for the fastest native API on each hot path: document-level delegation resolves a handler with
   `Element.closest()` (one native ancestor-walk, no `composedPath()` array allocated per event), and
   `morph` reuses one `<template>` and patches attributes over the live `NamedNodeMap` with no `[...]`
   snapshot. A batched, deduped signals scheduler runs each effect at most once per propagation.

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
- **`SWAR` → `ADFCore` + SWAR-accelerated escaper — done.** `SWAR` (the byte-scan kernel, previously
  internal to ADJSONCore) now lives in `ADFCore` as a public primitive — its proper shared home (both
  ADJSON and ADHTML depend on ADFCore). `Escaper.writeEscaped` fast-forwards 8 bytes/step over safe runs.
  *Measured:* escape/prose ≈ 5.0 → 3.9 µs (−54% vs the original byte-by-byte) **and** escape/text-heavy
  (dense) ≈ 9.7 → 9.0 µs — SWAR is now faster on **both**, erasing the bulk-copy dense regression. The one
  unsafe op (an unaligned `UInt64` word load) is **bounds-proven** (`index + 8 <= count`), confined to the
  `withUTF8` closure, and never escapes — a stated invariant, not "guilty" unsafe.
  - *Deferred — ADJSON adopting `ADFCore.SWAR` (de-dup):* ADJSON's copy stays for now; deduping needs
    aligning ADFCore's import visibility (`public import`) across ADJSON's `@inlinable` encoder/tokenizer
    hot files — a focused ADJSON PR with its full suite (which needs `ADTestKit`, unavailable here).
  - *Deferred — `Span`/`RawSpan` for the entity escaper (A1):* the growable `[UInt8]` sink can't `append`
    a `Span` without an unsafe bridge yet (Span↔Array interop), so Span would relocate rather than remove
    unsafe; the current word load is already bounds-proven. Revisit as the Span/Array surface matures.
- **`borrowing _render` — attempted, reverted.** Making the `HTML._render` *requirement* `borrowing Self`
  is the only way to borrow in the generic lowering path (concrete witnesses don't help — generic
  `_HTMLPair`/`_HTMLArray` dispatch through the requirement's convention), but it's all-or-nothing and two
  conformers can't borrow: the `Component` default captures `html` in the `withValue` closure, and
  `_HTMLOptional` binds `if let … = html.wrapped` — both "borrowed and cannot be consumed." Workarounds
  reintroduce the copies the borrow was meant to remove, so by-value lowering stays (its copies are
  shallow CoW-bumps). Confirmed the original deferral was correct.

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
