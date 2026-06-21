# ``ADHTMLCore``

The Foundation-free engine behind ADHTML: an iterative, escape-by-default HTML renderer, serializable
reactive signals, and resumable hydration islands.

## Overview

`ADHTMLCore` is the engine ADHTML is built on — the ``HTML`` / ``Component`` value-type DSL, an **iterative
(non-recursive)** renderer over a flat opcode program, **context-aware escape-by-default** output encoding,
the serializable reactive layer (``Signal`` / ``Computed`` / ``Reactive``), and the hydration wire (resumable
``Island``s plus the inline state script the small client runtime resumes). Its only dependencies —
`OrderedCollections` and `ADFCore` (the `AD*` family's byte/hash primitives) — are themselves Foundation-free
with no transitive packages, so the core stays portable and `Sendable` throughout.

The umbrella `ADHTML` module re-exports everything here (`import ADHTML` sees the full core) and adds the
authoring macros (`@Component` / `@State` / `@Bound`), document assembly (`Page`), and the gated
transport/feature bridges. Depend on the `ADHTMLCore` product when you want only the engine.

```swift
import ADHTMLCore

let bytes = div {
    "Hello, "
    span { "world" }.class("name")
}
.class("greeting")
.renderBytes()
// <div class="greeting">Hello, <span class="name">world</span></div>
```

Every node is a `Sendable` value type that lowers itself onto the renderer's opcode program; there is no
shared mutable state and no recursion over the value tree, so a deeply nested document cannot overflow the
native stack.

## Topics

### Guides

- <doc:RenderingModel>
- <doc:Reactivity>

### The view DSL

- ``HTML``
- ``Component``
- ``Text``
- ``RawHTML``
- ``ForEach``
- ``When``
- ``HTMLBuilder``
- ``EmptyHTML``

### Rendering

- ``RenderTarget``
- ``HTMLProgram``
- ``DirectTarget``
- ``Renderer``
- ``RenderError``
- ``ArraySink``
- ``HTMLByteSink``

### Escaping

- ``Escaper``
- ``EscapeContext``
- ``URLScheme``

### Reactive state

- ``State``
- ``Signal``
- ``Computed``
- ``Reactive``
- ``ReactiveReadable``
- ``WireExpr``
- ``BinaryOp``
- ``UnaryOp``
- ``CellArena``
- ``CellID``
- ``ADHTMLRenderContext``

### Hydration & islands

- ``Island``
- ``IslandID``
- ``LoadStrategy``
- ``Region``
- ``RegionID``
- ``Behavior``
- ``BehaviorInvocation``
- ``DOMEvent``
- ``BindTarget``
- ``AppStore``

### Component-scoped assets

- ``ScopedStyle``
- ``Script``
- ``CSSScoper``
- ``AssetSink``

### The wire format

- ``WireSerializer``
- ``WireToken``
- ``WireValue``
- ``WireEncodable``
- ``WireError``

### Streaming

- ``AsyncRenderer``
- ``AsyncHTMLByteSink``
