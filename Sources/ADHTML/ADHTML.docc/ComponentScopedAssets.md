# Component-Scoped CSS & JS

Co-locate scoped styles and a little JavaScript on a genuinely bespoke widget — without abandoning the model
or the security posture.

## Overview

The declarative vocabulary (bindings, behaviors, actions) covers most interactive UI with zero author JS. For
a *genuinely bespoke* widget — a canvas chart, a drag-reorder grid, a third-party-embed wrapper — a
`Component` can co-locate **scoped CSS** and a **little JavaScript** as an additive escape hatch. Three rules
frame it:

1. **The body is the fallback.** The component `body` stays the source of truth and the no-JS rendering; the
   asset only *enhances*.
2. **`StaticString` trust.** Every asset value (CSS, inline JS, module name) is a `StaticString` — trusted,
   never user-interpolated — so no user data can reach a `<style>` / `<script>` body.
3. **One network primitive.** A widget's script reaches the network *only* through `ctx.action` — the same
   signed endpoint the declarative actions use. It can never open an unsigned channel.

## Scoped CSS

Declare `ScopedStyle` on a component. By default the CSS is **scoped**: every top-level selector
is confined under the component's `data-scope` ancestor, so it can only match inside that component.

```swift
@Component
struct PriceTag {
    static var style: ScopedStyle? {
        ScopedStyle("""
        .tag { color: var(--accent); font-variant-numeric: tabular-nums; }
        .tag.sale { color: crimson; }
        """)
    }
    var body: some HTML { span { … }.class("tag") }
}
```

`CSSScoper` rewrites the CSS server-side: `@media` / `@supports` recurse one level;
`@keyframes` / `@font-face` / `@import` are copied verbatim; a `:global(…)` selector or a `.global` class opts
out of scoping. Two instances of one component contribute a single deduped `<style>`, injected before the
inline state script so no-JS clients get the styling with no flash. Pass `.global` for page-wide CSS.

## Component JavaScript

Declare `Script` on a component — `.inline` for a small snippet, or `.module` for a bundled ES
module. The engine stamps a `data-component` mount root; after hydration the client runtime dispatches each
mount root to its registered function:

```swift
@Component
struct Sparkline {
    static var script: Script? { .module(name: "sparkline") }
    var body: some HTML { canvas().attribute("data-points", points) }
}
```

```js
// ClientRuntime/components/sparkline.js
ADH.mount("Sparkline", (root, ctx) => {
    const draw = () => { /* read root, render to the canvas */ };
    draw();
    window.addEventListener("resize", draw);
    return () => window.removeEventListener("resize", draw);   // teardown runs on morph-removal
});
```

The mount function receives `ctx = { root, action }`. `ctx.action(url, opts)` is the **only** network
primitive — it reuses the action interpreter's request core, so a widget can only reach the server through
the signed endpoint, with the `ADH-Request` header. A returned function is the teardown, run when the root is
reconciled away (so listeners/timers/observers don't leak across re-renders).

> Note: the mount registry exposes `ADH.mount(name, fn)`. Registration order versus runtime load order does
> not matter — a late registration mounts any matching roots immediately.

## Bundling modules

Inline scripts need no toolchain. `.module` scripts are bundled by **bun** — the build-time half of the
own-tooling boundary (bun owns JS bundling/minification; Swift owns CSS scoping). Drop a module under
`ClientRuntime/components/` and run:

```sh
bun run build:components
```

`build-components.js` bundles + minifies each module as a **content-hashed** file and writes a
`manifest.json` mapping each name to `{ file, integrity, bytes }`. The `integrity` is a Subresource Integrity
token (`sha256-<base64>`) computed at build time and pinned, by test, to the same value the `ADHTMLSRI`
helper produces — so a served module's integrity is identical whichever side computes it.

## Serving (gated `ADHTMLAssets`)

The gated `ADHTMLAssets` product loads the manifest and serves the modules. In a handler:

```swift
// once, at startup
let manifest = try AssetManifest(contentsOfFile: "Public/assets/manifest.json")

// per request — read the CSP nonce the CSPNonce middleware minted
let nonce = ctx.storage[CSPNonceKey.self]
return try ResponseContent.adhtmlAssets(PricingPage(), manifest: manifest, nonce: nonce)
```

`adhtmlAssets` renders the hydratable page (stamping the nonce on the injected `<style>` and inline
`<script>`s) and appends a `<script type="module" src="/assets/<hashed>.js" integrity="sha256-…"
nonce="…">` for each `.module` component on the page. Serve the bundles with ADServe's
`Static("/assets", root: "Public/assets")` (content-hashed, ETag/304, precompressed).

## Security guardrails

- **CSP nonce** on every injected `<style>` / `<script>` (the core stays nonce-free; the gated bridge stamps
  the request nonce from `CSPNonceKey`). No `unsafe-inline`.
- **SRI** on served modules — the browser refuses a tampered bundle.
- **No `eval`** — widgets register functions; `ctx.action` is the only network primitive.
- **`StaticString` trust** — no user data reaches a `<style>` / `<script>` body.
- **Dedupe + SSR fallback** — one `<style>` per component type; the body renders without JS.
