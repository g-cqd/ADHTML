# ADHTML client runtime

The hand-written, **dependency-free** JavaScript runtime that interprets ADHTML's hydration wire format
(RFC-0003 / ADR-0006). It is the *entire* upfront client JS for an interactive page — the static
perimeter ships **zero** JS; only islands load this.

- **Size**: **1.23 KiB gzipped** (2.4 KB raw) — well under the ≤ 6 KiB hard budget (`build.ts` gates it).
- **No dependencies, no Swift→WASM** (ADR-0006): a hydration runtime is DOM-bound glue, WASM's weakest
  axis. This is plain TypeScript built with bun's built-in bundler.
- **Versioned**: `WIRE_VERSION` must equal `ADHTMLCore.wireFormatVersion` (= 1); `parseState` rejects a
  mismatch, and a test asserts parity.

## Layout

| File | Role | Tested |
|---|---|---|
| `src/signals.ts` | Fine-grained push-pull signals + effects | ✅ bun |
| `src/wire.ts` | Parse the inline `application/adh-state+json` state into signals | ✅ bun |
| `src/behaviors.ts` | The closed behavior registry (`increment`/`toggle`/`set`) — mirrors Swift `Behavior` | ✅ bun |
| `src/runtime.ts` | DOM layer: delegated listener, `data-adh-bind:*` bindings, load directives, SSE `connect`, `hydrate()` entry | browser smoke (pending) |
| `build.ts` | `Bun.build` minify → `adh-runtime.min.js` + gzip ≤ 6 KiB gate | — |

## Commands

```sh
cd ClientRuntime
bun test            # unit tests for the DOM-free core (signals, wire, behaviors)
bun run build       # minify + size-gate -> adh-runtime.min.js (committed, SRI-pinned)
```

## How it works

1. `hydrate()` reads `<script type="application/adh-state+json" id="adh-state">` and reconstructs the
   cells as signals (positional: array index == the ref used by bindings/scope).
2. For each island (`data-adh-id`), it honors the `data-adh-on` loading contract
   (`load`/`idle`/`visible`/`media:(…)`) and then wires it.
3. Wiring = one delegated listener per event at the island root (walk `composedPath()`, find
   `data-adh-on:<event>="<behavior>#<cell>[#param]"`, run the behavior) + `data-adh-bind:text|value|class`
   effects that update the node when their signal changes.
4. `connect(url, state)` subscribes to an SSE endpoint and applies `patch` events to cells (live
   updates) — requires ADServe SSE support (`docs/integration/adserve-requirements.md`).

## Known gaps (follow-ups)

- **Browser smoke tests** for the DOM layer (delegated listener, bindings, directives) — the core logic
  is unit-tested; the DOM glue is correct-by-inspection pending a headless-browser test.
- **`IntersectionObserver`** for `data-adh-on="visible"` (currently wires immediately — correct, not lazy).
- **HTML morph** (idiomorph-style) for SSE `morph` events; **client computed recomputation** (Swift
  formulas aren't serialized — computed cells are server-updated via `patch`, or a future closed
  client-expression set). The served artifact's **Subresource-Integrity** hash is computed Swift-side
  (`ADHTMLSRI`, swift-crypto).
