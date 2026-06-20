# ADHTML client runtime

The hand-written, **dependency-free** JavaScript runtime that interprets ADHTML's hydration wire format
(RFC-0003 / ADR-0006). It is the *entire* upfront client JS for an interactive page — the static
perimeter ships **zero** JS; only islands load this.

- **Size**: **1.64 KiB gzipped** (3.7 KB raw) — well under the ≤ 6 KiB hard budget (`build.ts` gates it).
- **Zero runtime dependencies, no Swift→WASM** (ADR-0006): a hydration runtime is DOM-bound glue,
  WASM's weakest axis. This is plain TypeScript built with bun's built-in bundler. (The only
  dev-dependencies are `@happy-dom/global-registrator` + `@types/bun`, used by tests/typecheck — never
  bundled.)
- **Versioned**: `WIRE_VERSION` must equal `ADHTMLCore.wireFormatVersion` (= 1); `parseState` rejects a
  mismatch, and a test asserts parity.

## Layout

| File | Role | Tested |
|---|---|---|
| `src/signals.ts` | Fine-grained push-pull signals + effects | ✅ bun |
| `src/wire.ts` | Parse the inline `application/adh-state+json` state into signals | ✅ bun |
| `src/behaviors.ts` | The closed behavior registry (`increment`/`toggle`/`set`) — mirrors Swift `Behavior` | ✅ bun |
| `src/morph.ts` | Lean id-aware DOM morph for SSE `morph` out-of-band swaps | ✅ happy-dom |
| `src/runtime.ts` | DOM layer: delegated listener, `data-adh-bind:*` bindings, load directives (incl. `IntersectionObserver`), SSE `connect`, `hydrate()` entry | ✅ happy-dom |
| `build.ts` | `Bun.build` minify → `adh-runtime.min.js` + gzip ≤ 6 KiB gate | — |

## Commands

```sh
cd ClientRuntime
bun install         # dev/test deps (happy-dom, @types/bun) — not bundled
bun run typecheck   # tsc --noEmit, strict
bun test            # DOM-free core (signals/wire/behaviors) + DOM layer under happy-dom
bun run build       # minify + size-gate -> adh-runtime.min.js (committed, SRI-pinned)
```

## How it works

1. `hydrate()` reads `<script type="application/adh-state+json" id="adh-state">` and reconstructs the
   cells as signals (positional: array index == the ref used by bindings/scope).
2. For each island (`data-adh-id`), it honors the `data-adh-on` loading contract: `load` (now),
   `idle` (`requestIdleCallback`), `visible` (`IntersectionObserver`, lazy until it scrolls in — with
   an immediate fallback when the API is absent), `media:(…)` (`matchMedia`) — then wires it.
3. Wiring = one delegated listener per event at the island root (walk `composedPath()`, find
   `data-adh-on:<event>="<behavior>#<cell>[#param]"`, run the behavior) + `data-adh-bind:text|value|class`
   effects that update the node when their signal changes.
4. `connect(url, state)` subscribes to an SSE endpoint and applies live updates: `patch` events set
   cells (fine-grained), `morph` events reconcile an island's subtree to new server HTML (preserving
   focus/state by id, via `morph.ts`). Requires ADServe SSE support
   (`docs/integration/adserve-requirements.md`).

## Known gaps (follow-ups)

- **Full idiomorph-style reordering** in `morph.ts`: v1 reconciles positionally with id preference
  (correct — the DOM ends matching the new HTML — and focus/state survive by id), but does not yet
  reorder keyed children to minimize moves.
- **Client computed recomputation**: Swift `Computed` formulas aren't serialized, so computed cells are
  server-updated via SSE `patch` (or a future closed client-expression set), not recomputed in-browser.
- The served artifact's **Subresource-Integrity** hash is computed Swift-side (`ADHTMLSRI`, swift-crypto).
