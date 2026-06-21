# RFC 0003 — Reactivity, hydration & the wire format

- **Status**: Proposed
- **Date**: 2026-06-19
- **Area**: Reactivity / hydration / client runtime
- **Depends on**: `ADJSON` (state serialization, `JSONMergePatch`), `ADFCore` (`XXH64` island IDs), RFC-0002 (rendering)
- **Related**: ADR-0004 (signals), ADR-0005 (islands), ADR-0006 (JS runtime), ADR-0007 (wire format), ADR-0012 (SSE transport)

## Summary

This is the novel subsystem — the reason ADHTML exists rather than adopting Elementary. A
**server-evaluated, wire-serializable signal graph** drives both the initial HTML and a **resumable
islands** hydration model: the server serializes listeners + island-scope state into the document, and
a **~2–4 KB hand-written JS runtime** (ADR-0006) resumes interactivity with no full-tree hydration and
no replay of view logic. Live updates are server-pushed over **SSE** as HTML morphs and **JSON Merge
Patch (RFC 7396)** signal patches. It is the largest review surface; the security crux is that **only
island-scope state is serialized** (a data-leak guard).

## 1. Why not full hydration, why not whole-page resumability

- **Full hydration** (React/Vue/Svelte default) re-executes component code on the client to rebuild
  the tree and attach listeners. A Swift server has no shared view code to re-run on the client, so
  full hydration means authoring and shipping a *second* implementation of every component — the worst
  case for bundle size and time-to-interactive. **Rejected.**
- **Whole-page resumability** (Qwik) is the right *mechanism* but the wrong *scope* here: it presumes
  an optimizer that code-splits *your component code* into lazy QRL chunks. ADHTML has no JS component
  layer to split. **We adopt Qwik's serialization mechanics, not its whole-page model.**
- **Islands + resumable wiring** (Astro topology × Qwik mechanics × Solid/Svelte-5 signals) is the
  fit: the server emits wiring + state *as data*; a generic runtime interprets it. ADR-0005.

## 2. Reactivity: serializable signals (ADR-0004)

A fine-grained signal graph — `Signal<Value>` (a reactive cell), `Computed<Value>` (a derived cell
with captured dependencies) — **not** Swift `Observation`/`@Observable`. `@Observable` tracks access at
runtime for SwiftUI invalidation; it is **not serializable to a wire format** and not designed to
linearize a value graph. ADHTML's cells are:

- **Server-evaluated** for the initial render (a `Signal`'s current value renders into the HTML);
- **Wire-serializable** — each cell keeps its creation index; the graph linearizes to JSON (§4);
- `Sendable` value types with a `CellID` that is the cell's **creation index in Phase 1** (deterministic
  across identical renders). A later refinement derives it from the render-scope path via `ADFCore.XXH64`
  so the same component tree yields the same IDs under structural reordering — required only once SSE
  morph/patch targets cells across renders (today's cross-render patching assumes byte-identical re-renders).

Fine-grained (not virtual DOM): the client runtime updates only the DOM nodes bound to a changed cell,
the Solid/Svelte-5 model. ADR-0004 documents the honest divergence from native `Observation`.

## 3. Islands + resumable wiring (ADR-0005)

An **island** is an opt-in subtree marked for client interactivity. The static perimeter stays plain
Swift-rendered HTML with **zero** JS. Each island carries:

- a stable `data-adh-id`;
- a **loading contract** `data-adh-on="load|idle|visible|media(<query>)"` (Astro's directive — the
  runtime wires it on load / `requestIdleCallback` / `IntersectionObserver` / `matchMedia`);
- **listener wiring as attributes** — `data-adh-on:click="<behavior>#<cellRef>"` — where `<behavior>`
  names a member of a **closed, exhaustive Swift `Behavior` enum** (set/toggle/increment/bind/submit…)
  the runtime interprets, and `<cellRef>` indexes the state graph. This is Qwik's
  `on:click="chunk#sym[0]"` mechanic, but resolving to a *known behavior* rather than a per-component
  code chunk — because behaviors are a closed set authored in Swift, not arbitrary compiled JS
  (RFC-0004/ADR-0009);
- **declarative bindings** — `data-adh-bind:text|value|class="<cellRef>"` (Datastar's `data-*` model).

The runtime **resumes**: it does not rebuild the tree or replay view code; it reads the wiring +
state and attaches a single delegated listener. ADR-0006.

## 4. The wire format v1 (ADR-0007)

One inline document-level script holds the state graph, serialized **through `ADJSON`** (no bespoke
JSON writer):

```html
<script type="application/adh-state+json" id="adh-state">
{ "v": 1,
  "cells": [ {"$":"sig","v":0},                 // 0: a signal, value 0
             {"$":"cmp","d":[0],"e":"toString"} // 1: computed from cell #0
           ],
  "islands": [ { "id":"c1", "on":"visible", "scope":[0,1],
                 "bindings":[ {"t":"on","ev":"click","b":"increment","c":0,"by":1},
                              {"t":"text","c":1} ] } ] }
</script>
```

- **Versioned** (`"v":1`) — the runtime refuses an unknown major and a CI test asserts the shipped
  runtime matches the emitted version (ADR-0006).
- **Index-deduped** — `cells` is an index array; references are integers (`"c":0`, `"d":[0]`), so
  shared and cyclic cells serialize once (React-Flight's `$`-ref idea, Qwik's `q:obj` index map, but
  JSON-native so a tiny parser handles it). `$`-tagged objects mark cell types so the runtime
  reconstructs reactive cells, not plain values.
- **Scoped** — `islands[].scope` lists only the cell indices reachable from that island; nothing else
  is serialized (§6).

## 5. Server push (SSE + Merge Patch) (ADR-0007, ADR-0012)

For live updates the server keeps an SSE stream (`text/event-stream`) and emits:

- `event: morph` — an HTML fragment morphed into a target by `id` (out-of-band swap), for
  server-rendered region updates;
- `event: patch` — a **JSON Merge Patch (RFC 7396)** over the cell graph, applied to client signals;
  emitted via `ADJSONCore`'s `JSONMergePatch` (reuse, not re-implement — ADR-0011).

Because Swift already owns canonical state, signal patches are a natural server output. This pairs with
the event log; SSE transport is ADServe ADR-0046 (sequenced via ADR-0012).

## 6. Security: the island-scope allowlist (the crux)

The dominant risk is **over-serialization** — leaking private read-model fields into the HTML — versus
**under-serialization** breaking hydration. Resolution (Marko's model): a cell's **value** is wire-serialized
**only if reachable from a declared island scope**. A non-island cell's value, kind, and formula are never
emitted — if its creation index sits below a reachable one it is replaced by a null placeholder (so bound
cells keep their index, §4), carrying no server data; otherwise it is simply omitted. A test asserts that a
non-island `@State`/read-model field's value never appears in any payload. The
state `<script>` is encoded in the `scriptJSON` context (`</`→`<\/`, U+2028/2029 escaped) to prevent
`</script>` breakout (ADR-0003), and is CSP-compatible via a nonce/hash; the runtime asset is
SRI-pinned (ADR-0006).

## 7. Failure-safe behavior

- The runtime is **additive**: with JS disabled or the runtime failing to load, server-rendered HTML
  and hypermedia links/forms still work (progressive enhancement).
- A version-skew (`"v"` mismatch) is detected at runtime and degrades to non-interactive, never a hard
  break.
- Serialization is bounded (cell-count and payload-size caps; cycles handled by the index refs, never
  an infinite loop — the serializer is iterative, ADR-0007).

## 8. Verification

- An island completes an interaction (increment/toggle/bind) with no full-tree hydration; the runtime
  attaches one delegated listener (DOM smoke test, headless browser — the one place a real browser is
  in the loop).
- Non-island state never appears in any wire payload (unit test over the serializer).
- Wire round-trip: `serialize(graph)` then parse-and-rebuild equals the original (shared/cyclic cells
  collapse to one ref); differential parse via `ADJSON` confirms well-formed JSON.
- An SSE `patch` applies via `JSONMergePatch` and updates exactly the bound nodes.
- The runtime asset stays ≤ 4 KB gzipped (hard CI gate).

## References

[Qwik resumability](https://qwik.dev/docs/concepts/resumable/) ·
[qwikloader](https://qwik.dev/docs/advanced/qwikloader/) ·
[Astro islands](https://docs.astro.build/en/concepts/islands/) ·
[Datastar data attributes](https://data-star.dev/guide/data_attributes_reactive_signals) ·
[RFC 7396 JSON Merge Patch](https://www.rfc-editor.org/rfc/rfc7396) ·
[React Flight protocol](https://react.dev/reference/rsc/server-components) ·
[SolidJS fine-grained reactivity](https://docs.solidjs.com/advanced-concepts/fine-grained-reactivity) ·
[Swift Observation](https://developer.apple.com/documentation/observation).
