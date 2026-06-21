# ``ADHTML``

A reactive, hydratable, Swift-only server-side rendering engine — type-safe HTML that becomes interactive
without a JavaScript framework.

## Overview

ADHTML renders type-safe HTML to bytes for a SwiftNIO server and emits **hydration state plus a tiny client
runtime**, so server-rendered markup resumes as interactive UI — with no second copy of your view logic.
There are **no template files**: views, components, and client behaviors are all `.swift`, so the entire
server scope type-checks and compiles as one unit. `swift build` is the template compiler.

One constraint shapes the design: the SSR host is Swift (NIO), which cannot run JavaScript server-side. So
ADHTML renders HTML *in Swift* and ships *state + a small generic runtime* for the client — never re-running
your views in the browser. The result is type-checked end to end (phantom-typed elements reject illegal
attribute combinations at compile time; the client-behavior vocabulary is a closed `enum`), rendered by an
iterative (non-recursive) engine with escape-by-default encoding, and made interactive by resumable islands
over a ~4.5 KiB hand-written runtime — not Swift→WASM.

```swift
import ADHTML

// Static markup
let html = div { "Hello, "; span { "world" }.class("name") }.render()

// An interactive island — no Island / scope / .id ceremony
@Component
struct Counter {
    @State var count = 0
    var body: some HTML {
        div {
            button { "+" }.on(.click, Behavior.increment(countSignal))
            span { String(count) }.bind(.text, to: countSignal)
        }
    }
}
```

`@State` makes `Counter` an island automatically: the macro adds the `countSignal` handle, infers the
hydration scope from the cells the component touches, and wraps the body in island markup. The server renders
`<span>0</span>` for no-JS clients; the runtime resumes the button + binding when the page loads.

> Note: the engine internals — the iterative rendering model and the reactivity/wire spec — are documented in
> the **`ADHTMLCore`** reference (its *Rendering Model* and *Reactivity & the Hydration Wire* articles).

## Topics

### Essentials

- <doc:GettingStarted>

### Guides

- <doc:InteractiveComponents>
- <doc:DerivedState>
- <doc:MarkdownInBuilder>
- <doc:ComponentScopedAssets>

### Authoring macros

- ``Component()``
- ``State()``
- ``Bound()``
- ``attr(_:)``

### Document assembly

- ``HTMLDocument``
