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
