# ADR 0021 — Component-scoped CSS & JS (the declarative-first escape hatch)

- **Status**: Accepted (A1 + A2 + A3 landed; the live NIO/Playwright e2e is the app-migration milestone)
- **Date**: 2026-06-21
- **Related**: ADR-0003 (escape-by-default), ADR-0005 (islands), ADR-0006 (tiny JS runtime), ADR-0011
  (ADFCore/SRI reuse), ADR-0012 (ADServe integration), ADR-0019 (wire-token vocabulary), RFC-0006
  (client-dynamic-content + the **declarative-first, permitted component-scoped JS** principle this amends).

## Context

ADHTML's P1–P9 vocabulary (bindings, behaviors, actions, lists, conditionals) is declarative and covers the
overwhelming majority of interactive UI with zero author JS. But a genuinely bespoke widget — a custom
canvas chart, a drag-reorder grid with physics, a third-party-embed wrapper — sometimes needs co-located CSS
and a little imperative JS. The declarative-first principle (RFC-0006) PERMITS author JS as a sanctioned
escape hatch, provided it cannot subvert the model or the security posture.

## Decision

Add **component-scoped assets** as an ADDITIVE escape hatch (never a replacement for P1–P9): a `Component`
co-locates a `ScopedStyle` and/or a `Script`. The component `body` stays the source of truth + the no-JS
fallback; the asset only ENHANCES. Three guarantees frame the design:

1. **The body is the fallback.** A no-JS client gets the rendered body + the scoped CSS (injected inline);
   the script only enhances.
2. **`StaticString` trust.** Every asset value (`css`, inline JS, module name) is a `StaticString` — trusted,
   never user-interpolated — so no user data can reach a `<style>`/`<script>` body. (The `RawHTML`-grade
   bypass, but narrower: it cannot carry runtime data at all.)
3. **One network primitive.** A widget's script reaches the network ONLY through `ctx.action` — the signed
   RFC-0019 endpoint, with the `ADH-Request` header — which reuses the action interpreter's `request` core.
   It can never re-implement the model or open an unsigned channel.

### The own-tooling boundary (the settled bun/Swift split)

- **Swift owns CSS scoping + minification** — small, server-side, render-time. `CSSScoper` is a Swift-native
  single-pass byte state machine (no process-global cache; the `AssetSink` dedups by scope hash before
  scoping). Foundation-free, in the unconditional core.
- **bun owns JS bundling + minification** — large, build-time, security-sensitive (tree-shaking, module
  resolution). `ClientRuntime/build-components.js` bundles each `.module` as a content-hashed, SRI-pinned ES
  module + a `manifest.json`; the runtime mount bridge folds into the 4.5 KiB budget.
- **A Swift-native JS lexer/bundler is a documented FUTURE investigation, not committed.** Re-implementing a
  correct, secure JS bundler in Swift is a large undertaking with no near-term payoff; bun is the pragmatic
  choice now. (A tiny Swift-native CSS minifier may follow — CSS is far simpler.)

### A1 — CSS scoping + asset accumulation + injection (core, unconditional)

- `ScopedStyle(StaticString, .scoped/.global/.shadow)` + `Component.style { nil }`. `.scoped` confines every
  top-level selector under a `[data-scope="<hash>"]` ancestor (`CSSScoper`); `@media`/`@supports` recurse one
  level; `@keyframes`/`@font-face`/`@import` verbatim; `:global`/`.global` opt out. Documented boundary (not
  a full CSS parser): out-of-scope constructs degrade to one prefixed selector, never invalid CSS.
- `AssetSink` (`Mutex`-guarded, mirrors `CellArena`) on `ADHTMLRenderContext.Context`; `child()` forwards it;
  `nil` on the static `render()` path. Dedup key = `base36(XXH64(typeName + css + script))`.
- `Component._render` stamps a `data-component`/`data-scope` mount root (new wire tokens `data-0`/`data-1`,
  regenerated from `wire-tokens.json`). An interactive styled component nests its island INSIDE the mount
  root; a static asset-bearing component gets the mount root with no wire cells. `renderHydratable` (buffered
  + streaming) injects the deduped `<style>` BEFORE the inline state script — present in the initial response,
  so no-JS gets the CSS and there is no FOUC.

**Wrapper-root vs `islandOpen` extension (a refinement of the plan):** the mount root is a distinct wrapper
`<div data-component data-scope>` rather than extra attributes threaded through `islandOpen`. This keeps the
`RenderTarget`/`HTMLOp`/`Renderer` surface untouched, cleanly separates concerns (island = hydration,
mount root = assets), and costs one wrapper div for an asset-bearing interactive component — an acceptable
trade for zero churn on the hot render path.

### A2 — the mount bridge + inline scripts

- `mount.js` (folded into the 4.5 KiB runtime, at budget): after `hydrate()`, dispatch over
  `[data-component]` roots and run each registered `ADH.mount(name, fn)`. The `ctx` is the minimal secure
  core — `{ root, action }` — where `ctx.action` is the only network primitive (the shared `request`).
  A mount fn may RETURN a teardown, run when its root is morphed away (`runCleanups` in `morph.js`'s remove
  path — no leaked listeners across re-renders). Late registration mounts immediately, so script-vs-runtime
  order doesn't matter. (Richer `ctx` members — `data`/`signal`/`morph`/`onCleanup` — are a budget-gated
  follow-up; the returned-teardown pattern already covers cleanup.)
- `Script.inline(StaticString)` → a `<script>` injected after the `<style>`, before the state script (so the
  mount fn registers before the runtime drives the bridge). `Script.module(name:)` → A3.

### A3 — module bundling + serving (the gated bridge) — landed

- `build-components.js` (bun): globs `ClientRuntime/components/*.js`, bundles each as a content-hashed ES
  module + a `manifest.json` (`name → {file, integrity, bytes}`); SRI = `sha256-<base64>` via
  `Bun.CryptoHasher`, PARITY-pinned to `ADHTMLSRI.integrity(for:)` (the same standard padded base64 of
  SHA-256) — proven by a ClientRuntime test asserting the SAME known answer ADHTMLSRITests pins.
- The core exposes the seam the bridge needs WITHOUT I/O: `renderHydratable(arena:nonce:assets:)` takes an
  optional CSP `nonce` (stamped on the injected `<style>`/inline-`<script>`; `nil` keeps the core nonce-free,
  byte-identical) and an optional caller-provided `AssetSink` (so the bridge can read the page's `.module`
  names afterward). The core never touches the manifest or generates a nonce.
- Gated `ADHTMLAssets` bridge (`ADHTML_ASSETS`; deps `ADHTMLCore` + `ADHTMLNIO` + ADServeCore;
  `needsNIO = isNIO || isActions || isAssets`): an `AssetManifest` model (decodes the bun manifest) + a
  `ResponseContent.adhtmlAssets(_:manifest:nonce:assetPath:)` that renders nonce-stamped, then APPENDS a
  `<script type=module src=/assets/<file> integrity=<sri> nonce=<nonce>>` per `.module` component (a module
  absent from the manifest is skipped). Module scripts are `defer`red, so appending them after the inline
  state script is correct (the mount bridge late-mounts). The bridge TRUSTS the manifest's build-time SRI —
  no swift-crypto runtime dep. Serve with ADServe `Static("/assets", root:)`; mint + read the nonce via the
  `CSPNonce` middleware / `CSPNonceKey`. `.inline` scripts get a `<script nonce>` (no SRI — part of the HTML,
  covered by CSP). The live loopback proof (a served page mounts a module under a strict CSP) is the
  NIO/Playwright e2e in the app-migration milestone.

## Guardrails

CSP nonce on every injected `<style>`/`<script>` (stamped by the gated bridge); no `eval` (registered
functions only, `ctx.action` the only network primitive); dedupe by scope hash; SSR/no-JS fallback; SRI on
served modules; `StaticString` trust (no user data reaches a `<style>`/`<script>` body); no `unsafe-inline`.

## Consequences

- **Positive:** a bespoke widget is expressible without abandoning ADHTML's model or security posture; the
  declarative path stays the default; CSS scoping is Foundation-free + render-time; the JS budget holds.
- **Negative / bounded:** one wrapper div per asset-bearing component; `CSSScoper` is a documented byte
  state machine, not a full CSS parser; the bun toolchain is a build-time dependency for `.module` scripts
  (inline scripts need no toolchain); a Swift-native JS bundler is deferred.
- **Invariants kept:** escape-by-default; the declarative vocabulary is primary; the wire format unchanged;
  the runtime within 4.5 KiB; the macOS-15/iOS-18 floor.
