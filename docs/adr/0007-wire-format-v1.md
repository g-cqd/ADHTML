# ADR 0007 — Wire format v1 (versioned, index-deduped, ADJSON-serialized)

- **Status**: Proposed
- **Date**: 2026-06-19
- **Related**: RFC-0003; ADR-0004 (signals), ADR-0006 (runtime), ADR-0011 (ADJSON reuse), ADR-0012 (SSE)

## Context

Hydration needs a wire contract that ships island boundaries + reactive state from Swift to the
browser compactly and safely, supports shared/cyclic cells without duplication or infinite loops, and
is parseable by a tiny JS runtime. Prior art: React-Flight's `$`-referenced line protocol, Qwik's
`q:obj` index map, Datastar's `data-*` signals + SSE.

## Decision

**Wire format v1**, three surfaces:

1. **Island attributes** on the island root — `data-adh-island`, `data-adh-id`, `data-adh-on`
   (`load|idle|visible|media(...)`), `data-adh-on:<event>="<behavior>#<cellRef>"`,
   `data-adh-bind:<text|value|class>="<cellRef>"`.
2. **One inline state graph** — `<script type="application/adh-state+json" id="adh-state">` carrying
   `{ "v":1, "cells":[…], "islands":[…] }`: `cells` is an index array; references are integer indices
   (`"c":0`, `"d":[0]`) so shared/cyclic cells serialize **once**; `$`-tagged cells mark type
   (`sig`/`cmp`/`ref`). Serialized **through `ADJSON`** (no bespoke writer). `islands[].scope` lists
   only the cell indices reachable from that island (the data-leak guard, ADR-0005).
3. **Server push** over SSE — `event: morph` (HTML OOB swap by `id`) and `event: patch` (a JSON Merge
   Patch, RFC 7396, over the cell graph, emitted via `ADJSONCore.JSONMergePatch`).

The serializer is **iterative** (two passes: assign indices via an identity map, then linearize with
an explicit stack), so cycles/shared cells are handled with no recursion and no infinite loop. The
format is **versioned** (`"v":1`); the runtime refuses an unknown major; a CI test asserts the shipped
runtime matches the emitted version.

## Consequences

- **Positive**: compact (dedup), cycle-safe, JSON-native (tiny parser), reuses `ADJSON` +
  `JSONMergePatch` (no duplication, ADR-0011); the `scope` allowlist bounds payload and prevents data
  leaks; versioning enables forward evolution.
- **Negative**: a documented schema to keep in lockstep with the runtime — mitigated by the version
  field + CI parity test and `WireEncodable` round-trip property tests.
- **Security**: the inline `<script>` is `scriptJSON`-escaped (ADR-0003) and CSP nonce/hash-compatible.

## Amendment — P5 op-table + array cells (RFC-0021, 2026-06-20)

The client-recomputable expression `e` (a `cmp` cell's formula) grows, on **both** sides together (a
Swift `UnaryOp`/`BinaryOp.allCases` ↔ JS `UNARY_OPS`/`BINARY_OPS` parity test), staying a closed set with
no `eval`:

- **A unary node** `{"u":op,"x":<expr>}` joins the existing leaf / `{"o",l,r}` binary node. Ops:
  `lc` (`String.lowercased`), `len` (`Collection.count`). The serializer's iterative encoder gains a
  `foldUnary` work item; the JS evaluator a `ufold`; `cellRefs` walks the operand. Forward-compatible: an
  older runtime returns `undefined` for an unknown op.
- **A `has` binary op** — substring (`String.includes`) OR array membership (`Array.includes`), the client
  picking by operand type. Yields `Bool`. Powers the combobox filter predicate (`item.lowercased().has(
  query.lowercased())`) and the exact-match guard.
- **Array cells** need **no** format change — `WireValue.array` (ADR-0004) already serializes
  `Signal<[String]>` as a JSON array; P3's client list and the `commit`/`removeLast` behaviors operate on
  it directly.
- `highlight(text, query)` is a runtime helper (not a wire node): it emits **escaped** text with the match
  wrapped in a literal `<mark>` — XSS-safe, no `RawHTML`, no user markup reaches the DOM (unit-tested).
- **`filter` + `element`** (P5, the combobox filter): `{"fl":<array>,"p":<predicate>}` keeps the array
  elements for which the predicate is truthy; the predicate references the current item as `{"el":1}`. The
  predicate is **not** pre-evaluated — the client re-enters the evaluator per item with the element bound
  (the evaluator gains an `element` parameter). Swift's eager `Reactive.value` computes the same filter
  server-side (it runs the predicate builder per element), so SSR and the client agree. `count` over a
  `filter` is the live bound for `listMove` keyboard navigation — the declarative combobox path.
