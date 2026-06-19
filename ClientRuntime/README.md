# ADHTML client runtime

This is **not** a Swift target. It is the hand-written, generic JavaScript runtime that interprets the
ADHTML hydration wire format (RFC-0003 / ADR-0006): a delegated-listener loader, a fine-grained
signals core, declarative DOM binding, and an SSE morph/patch client.

- **Target size**: ≤ 6 KB gzipped (hard CI gate — ADR-0006). This is the entire upfront client JS for
  an interactive page; the static perimeter ships **zero** JS.
- **Why not Swift→WASM**: a hydration runtime is DOM-bound glue, WASM's weakest axis (bundle 100–400×
  larger, cold-start, JS↔WASM boundary tax; Tokamak archived, carton deprecated). See ADR-0006.
- **Versioning**: the runtime is pinned to the wire-format version (`ADHTMLCore.wireFormatVersion`,
  currently `1`); a CI test asserts parity.
- **Integrity**: the minified artifact is committed and served with a Subresource-Integrity hash
  (SHA-256 via the gated `ADHTMLSRI`, ADR-0011).

## Status

`adh-runtime.js` here is a **specification stub** describing the contract; the implementation +
minify/SRI build (esbuild, dev-gated) lands with the reactivity subsystem. Nothing in the default
`swift build` depends on it.

## Wire format (summary)

Island roots carry `data-adh-island`, `data-adh-id`, `data-adh-on` (`load|idle|visible|media(...)`),
`data-adh-on:<event>="<behavior>#<cellRef>"`, and `data-adh-bind:<text|value|class>="<cellRef>"`. One
inline `<script type="application/adh-state+json">` carries the index-deduped cell graph
(`{ "v":1, "cells":[…], "islands":[…] }`). Server push is SSE: `event: morph` (HTML OOB swap) and
`event: patch` (JSON Merge Patch, RFC 7396). See `docs/adr/0007-wire-format-v1.md`.
