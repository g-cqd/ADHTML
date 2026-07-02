# Getting Started

Add ADHTML, render your first page, and make it interactive.

## Add the package

In `Package.swift`:

```swift
.package(url: "https://github.com/g-cqd/ADHTML.git", branch: "main")
```

Then depend on a product:

```swift
.target(name: "App", dependencies: [
    .product(name: "ADHTML", package: "ADHTML")          // the umbrella: core + macros + Page
])
```

- **`ADHTML`** — the umbrella you usually want: the engine, the `@Component` / `@Bound` macros, the `@State`
  property wrapper, `#attr`, and `Page`.
- **`ADHTMLCore`** — the Foundation-free engine on its own (DOM DSL, renderer, escaping, reactivity), if you
  want no macros.

> Important: build with **`--build-system native`**. ADHTML ships a `.macro` target; on current toolchains
> the newer `swiftbuild` engine mislinks the macro module into dependent test bundles. The classic `native`
> build system handles macros correctly, so all `swift build` / `swift test` / `swift package` commands take
> `--build-system native`.

## Optional, gated products

Heavier or host-coupling features are gated by an environment variable, so consumers of the default products
never resolve their dependencies. Set the variable when resolving/building to opt in:

| Product | Gate | What it adds |
|---|---|---|
| `ADHTMLServe` | `ADHTML_SERVE` (legacy alias: `ADHTML_NIO`) | the ADServe transport bridge (`.adhtml` / `.adhtmlStream` / SSE) |
| `ADHTMLMarkdown` | `ADHTML_MARKDOWN` | `Markdown` in a component body — see <doc:MarkdownInBuilder> |
| `ADHTMLAssets` | `ADHTML_ASSETS` | serving component-scoped JS modules — see <doc:ComponentScopedAssets> |
| `ADHTMLActions` | `ADHTML_ACTIONS` | signed server-action closures (`@Action` / `@Actions`) |
| `ADHTMLSRI` | `ADHTML_SRI` | Subresource Integrity tokens for the client runtime |

```sh
ADHTML_MARKDOWN=1 swift build --build-system native
```

> Note: the core component-scoped-asset *surface* (`ScopedStyle` / `Script`) is always available in
> `ADHTMLCore`; only the module *serving* bridge is gated behind `ADHTML_ASSETS`.

## Your first render

A static render needs no server and no runtime:

```swift
import ADHTML

let page = Page(head: {
    title { "Shop" }
    meta().attribute("charset", "utf-8")
}) {
    h1 { "Welcome" }
    p { "Static, type-safe, escape-by-default HTML." }
}

let bytes = page.render()   // String — ready to write to a response body
```

`Page` assembles `<!doctype html><html lang><head>…</head><body>…</body></html>` from a head slot and a
content slot, so you never hand-write the scaffold.

## Your first interactive component

Make it interactive by adding `@State`. The component becomes a hydration **island** automatically — you
write no `Island`, no `scope:`, and no `.id`:

```swift
@Component
struct LikeButton {
    @State var likes = 0
    var body: some HTML {
        div {
            button { "♥" }.on(.click, .increment($likes))
            span { String(likes) }.bind(.text, to: $likes)
        }
    }
}
```

Render it on the hydratable path so the inline state script is emitted alongside the markup:

```swift
let arena = CellArena()
let bytes = try LikeButton().renderHydratable(arena: arena)   // [UInt8]
```

The server renders `<span>0</span>` (the no-JS fallback); the client runtime reads the inline state and wires
the button + binding. See <doc:InteractiveComponents> for the full vocabulary; the `ADHTMLCore` reactivity
reference covers how the wire works.

> Note: a `@Component` body with multiple top-level statements should have a single root element (e.g. wrap
> them in `div { … }`). This is a Swift result-builder + macro-added-conformance limitation, not a runtime
> one.

## Build the documentation

The DocC plugin is dev-gated. To generate this documentation locally:

```sh
ADHTML_DEV=1 swift package --build-system native generate-documentation \
    --target ADHTMLCore --target ADHTML
```

## Requirements

- A **Swift 6.4** toolchain (the package pins the language mode and is built/tested on 6.4).
- Deployment floor **macOS 15 / iOS 18 / tvOS 18 / watchOS 11 / visionOS 2** — pinned by the stdlib
  `Synchronization.Mutex` the reactive arena uses.
