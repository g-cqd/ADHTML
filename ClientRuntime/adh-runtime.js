// ADHTML client runtime — SPECIFICATION STUB (not the implementation).
//
// This is the entire upfront client JS for an interactive page (target <= 6 KB gzipped, ADR-0006).
// The static perimeter ships zero JS; only islands load this. It is generic: it interprets the
// ADHTML hydration wire format (RFC-0003 / ADR-0007) and never contains app-specific view logic.
//
// The real implementation + minify/SRI build (esbuild, dev-gated) lands with the reactivity
// subsystem. The contract it must implement:
//
//   1. Read the inline state graph:
//        <script type="application/adh-state+json" id="adh-state">
//        { "v": 1, "cells": [...], "islands": [...] }
//      Refuse an unknown major "v" and degrade to non-interactive (server HTML still works).
//
//   2. Reconstruct fine-grained signals from `cells` (index-deduped; "$"-typed: sig/cmp/ref).
//
//   3. For each island (data-adh-id), honor its loading contract data-adh-on:
//        load    -> wire immediately
//        idle    -> requestIdleCallback
//        visible -> IntersectionObserver
//        media(q)-> matchMedia(q)
//
//   4. Attach ONE delegated listener at the document root (qwikloader-style). On an event, walk the
//      bubbling path for a data-adh-on:<event>="<behavior>#<cellRef>" attribute and run the named
//      behavior from the closed registry (set/toggle/increment/bind/submit/...) against the cell.
//
//   5. Bind data-adh-bind:text|value|class="<cellRef>" so a cell change updates exactly that node.
//
//   6. Server push over SSE: `event: morph` -> morph an HTML fragment into a target by id;
//      `event: patch` -> apply a JSON Merge Patch (RFC 7396) to the cell graph.
//
// See ClientRuntime/README.md and docs/adr/0006-tiny-js-runtime-not-wasm.md,
// docs/adr/0007-wire-format-v1.md.

throw new Error("adh-runtime: specification stub — not yet implemented");
