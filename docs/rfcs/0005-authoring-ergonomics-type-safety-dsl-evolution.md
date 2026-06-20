# RFC 0005 — Authoring ergonomics, type safety, and DSL evolution

- **Status**: Accepted (incremental implementation)
- **Date**: 2026-06-20
- **Related**: RFC-0001 (umbrella), RFC-0003 (reactivity/hydration), RFC-0004 (whole-scope compile),
  ADR-0005 (islands), ADR-0008 (lean macro surface), ADR-0009 (Swift-only, compile-time legality),
  ADR-0013 (perf/safety). Implemented by ADR-0014 (typed attribute enums) and ADR-0015 (reactive
  authoring ergonomics).

## 1. Motivation

The ADHTML **engine** is at or near the state of the art for its model: a single-pass, allocation-lean,
recursion-free renderer; escape-by-default; phantom-typed elements with compile-time attribute legality;
resumable islands over a 2.2 KiB JS runtime that, in a same-machine chromium comparison (500 SSR
counters), is second only to hand-written vanilla on time-to-interactive (1.9 ms vs ~5.3–5.5 ms for
React/Vue/Preact) and per-interaction latency (4.35 µs/click), and is the smallest runtime measured
(2.2 KiB vs 6.2 KiB Preact / 37.5 KiB Vue / 46.8 KiB React).

The remaining gap to "state of the art" is therefore **not** the engine — it is **authoring**: making
ADHTML as clean to write as SwiftUI, with lower cognitive load, lower cyclomatic complexity at the call
site, and stronger type safety. This RFC inventories the current friction (grounded in the code), sets
the design directions, and sequences the work. Two design tenets frame everything: **(a)** push errors
to compile time and values into the type system; **(b)** preserve the settled engine invariants
(zero `any`, escape-by-default, `consuming` modifier chains, the macOS-15/iOS-18 floor).

## 2. Current authoring friction (grounded)

| # | Friction | Where | Cost |
|---|---|---|---|
| F1 | Fixed-value attributes are stringly-typed: `target("_blank")`, `rel("noopener")`, `method("get")`, `type("email")`, `loading="lazy"` via the raw `.attribute(_:_:)` hatch | `DOM/Attributes+Standard.swift:9-86` | typos compile; no autocomplete; memorize valid sets |
| F2 | Most boolean attributes have no modifier — only `hidden`/`disabled` exist; `required`/`checked`/`selected`/`readonly`/`multiple`/`open`/… need `.attribute("required","")` by hand | `DOM/Attributes+Standard.swift:23,61` | correctness footgun (wrong/empty value), coverage gap |
| F3 | Island `scope:` is a hand-maintained allowlist of `signal.id`s | `Hydration/Island.swift:11-21`; usage `ComponentMacroTests.swift:23` | the subsystem's stated #1 hazard (ADR-0005): omit one → cell silently never hydrates |
| F4 | One piece of state is spelled three ways: `count` (value), `countSignal` (handle), `countSignal.id` (for `bind`) | `StateMacro.swift`; `Bindings.swift:19` | no `$count` projection; high cognitive load |
| F5 | A bound value is authored twice and can drift: `span { String(count) }.bind(.text, to: countSignal.id)` | `Bindings.swift:18-21` | the rendered default and the bound cell are unchecked against each other |
| F6 | Event names are bare `String`s: `.on("click", …)` | `Hydration/Bindings.swift:13-16` | `"clikc"` compiles |
| F7 | The client-recomputable expression set is `+ - * ++` only; anything else falls back to `computed { }`, which is **silently server-only** (no client recompute) | `Reactive/Expression.swift:99-113`; `CellArena.swift:62,78` | the two `computed` overloads look identical but behave very differently |
| F8 | No component-level computed/derived state (`computed` is arena-level, not reachable from `@Component`) | `CellArena.swift`; `HTML.swift` | derived values (a live total) aren't expressible in a component |
| F9 | No document/head conveniences: `meta().attribute("charset","utf-8")`, `meta().name("viewport").content(…)` | `Tests/.../ElementsTests.swift:12-13`; `PerfProbe/main.swift:64-86` | boilerplate on every page |
| F10 | No component children/slots: a `Component` can't take `{ … }` content | `DOM/HTML.swift:10-21` | can't write `Card { … }` / layout shells |
| F11 | No accessibility surface beyond generic `.role(String)`/`.aria(_:_:)` | `DOM/Attributes+Standard.swift:17,27` | a11y is undiscoverable and untyped |

## 3. Design directions

### 3.0 Implicit islands — abstract the hydration boundary out of developer code (the headline)

The single biggest ergonomic leap: **the developer never writes `Island(...)` or a `scope:` list.** They
write components, `@State`, computed/derived properties, events, and bindings — plain SwiftUI-shaped code
— and the framework decides the hydration boundaries. "Island" becomes an *implementation detail of an
interactive component*, not an authoring concept.

Mechanism:
- **`@Component` classifies itself.** At expansion the macro sees whether the type has any `@State` /
  `@Derived` members (or interactive modifiers) and conforms it to a marker `Interactive`. A component
  with reactive state *is* an island; a purely static one renders inline (zero island, zero JS) — exactly
  the two-tier model (ADR-0005), now inferred instead of hand-marked.
- **`Component._render` wraps interactive components automatically** in the island markup
  (`<div data-adh-island data-adh-id=… data-adh-on=…>…</div>`), with:
  - **id** derived from the render-scope path hash (the stable `CellID` mechanism, RFC-0003 §2) — stable
    across renders, which also unblocks SSE `morph` targeting.
  - **scope** *inferred* = the cells created/touched within this component's render scope. The ambient
    `ADHTMLRenderContext` already opens a fresh scope per component instance (`HTML.swift:23-36`) and
    records cell reads (`Signal.value → arena.recordRead`); the island collector reads that set. (This is
    §3.2's scope inference, now applied to the *implicit* boundary.)
  - **loading** = `.load` by default; overridable with `@Component(hydrate: .visible)` or a
    `.hydration(.visible)` modifier at the use site.
- **Explicit `Island(...)` remains** as a low-level escape hatch for grouping non-component subtrees, but
  the common path never names it.
- **Composition just works:** a nested interactive component becomes its own island (per-instance scopes
  already isolate their cells), so islands nest/compose without the author thinking about it.

Net effect: developer-facing code has **no `Island`, no manual `scope`, no `.id` ceremony** — only state,
derived values, events, and bindings. (See §7 for a whole app written this way.)

### 3.0b Rely on computed/derived properties

Pairing with implicit islands, derived state should be ordinary-looking Swift:
- **`@Derived var total = $apples + $oranges`** (assignment form) builds a client-recomputable `Reactive`
  and exposes a `Computed` handle — the pragmatic form, available as soon as the wider expression set
  (§3.5) lands.
- **Aspiration — macro-parsed computed bodies:** `@Derived var total: Int { apples + oranges }` where the
  macro translates the body into a `WireExpr` over the closed op set; an expression outside the set is a
  compile diagnostic (or an opt-in `@ServerComputed` that is server-fixed). This is the "just write a
  computed property" ideal, bounded by what the client can re-evaluate.
- A plain `var doubled: Int { count * 2 }` already yields the correct **server** value today (it reads
  `count.value`); the macro forms above are what make it **client-reactive**.

### 3.1 Type-safe attribute values — **ADR-0014** (this pass)
Replace stringly-typed fixed-value attributes with `enum X: String, Sendable` plus a modifier that is
**gated exactly like today** (existing trait where one exists; per-element `where Tag == Tags.X`
otherwise) so compile-time *legality* is preserved and compile-time *value validity* is added. Keep the
`String` overload (and/or a `.custom`/`frame:` escape) for author-defined or future tokens. Closes F1.
Adds the missing boolean modifiers (F2). Adds typed ARIA (`role`, `aria-*`) — the first real a11y
surface (F11).

### 3.2 Reactive authoring ergonomics — **ADR-0015** (this pass)
- **Typed events** (F6): `DOMEvent` enum → `.on(.click, …)`, with `.on("custom", …)` retained.
- **Signal-based bindings** (F4): `.bind(.text, to: signal)` overload taking a `Signal`/`Computed`
  directly (drops the `.id` ceremony); the `CellID` overload stays.
- **Island scope inference** (F3): `Island` lowers its content inside the ambient
  `ADHTMLRenderContext`; have that context record every `CellID` *touched* (by `.bind`/`.on`/`Reactive`)
  during the island's lowering and default `scope` to that set. Explicit `scope:` remains as an override
  / escape hatch. This removes the #1 hazard *and* the boilerplate.

### 3.3 Reactive interpolation + initial-value auto-fill (next)
Make `.bind(.text, to: signal)` auto-fill the element's initial text from the bound cell's current value
(read from the ambient arena) when the element has no content, so a value is authored once and cannot
drift (F5). Direction: `span { }.bind(.text, to: count)` renders `<span data-adh-bind:text="0">0</span>`.

### 3.4 `$state` projection (next, evaluated against the memberwise-init tradeoff)
Offer a property-wrapper form of `@State` with `init(wrappedValue:)` so `count` is the value and `$count`
is the `Signal` (SwiftUI parity), collapsing F4 to a single name. Tradeoff: the stored type becomes
`State<Int>`; the parent-supplied server seed still works via `init(wrappedValue:)`. Prototype behind the
existing peer macro before committing.

### 3.5 `@Derived` + wider expression set + explicit server-only (next)
- `@Derived var total = $apples + $oranges` — a component-level client-recomputable computed (F8).
- Widen `WireExpr`/`BinaryOp` (and the JS evaluator, with the parity test) with `/`, comparisons
  (`== != < <= > >=`), boolean (`&& || !`), and a ternary (F7).
- Rename the opaque path to `serverComputed { }` so losing client reactivity is explicit, not silent.

### 3.6 Document/head conveniences (next)
`Document(title:lang:) { }`, `meta.charset(.utf8)`, `meta.viewport()`, `Stylesheet("/app.css")`,
`Favicon(…)` — small components/modifiers over the raw element constructors (F9).

### 3.7 Component composition / slots (next)
Let a `Component` accept `@HTMLBuilder` children so `Card { … }` / `PageLayout { … }` are expressible
(F10), enabling real app shells.

### 3.8 Accessibility (folded into 3.1, then extended)
Typed `role` + `aria-*` (3.1) is the entry; follow with landmark helpers and an a11y section in the docs
and example app (F11).

## 4. Roadmap & sequencing

| Pass | Scope | ADR | Risk |
|---|---|---|---|
| 1 | Typed attribute enums + boolean modifiers + typed ARIA (3.1) | ADR-0014 | low (purely additive, one new file) |
| 2 | Typed events + Signal-based bindings + island scope inference (3.2) | ADR-0015 | low–medium (render-context change for scope) |
| 3 | Reactive interpolation/auto-fill (3.3) + `$state` (3.4) | (future ADR) | medium (renderer + macro) |
| 4 | `@Derived` + wider expression set (3.5) | (future ADR) | medium (Swift+JS parity) |
| 5 | Document/head conveniences (3.6) + component slots (3.7) | (future ADR) | low–medium |
| — | Transport: SSE + streaming response + `text/html` (RFC-0003 live updates) | ADR-0012 | blocked on ADServe |

## 5. Non-goals / invariants preserved

- **Zero `any`** — no `AnyHTML`; control flow stays in the builder (`_HTMLEither`/`buildOptional`).
- **No `@dynamicMemberLookup` for attributes** — it would trade compile-time legality for stringly-typed
  access (rejected, ADR-0008/0013). Enums move the *opposite* direction.
- **Escape-by-default** — enum `rawValue`s are known-safe ASCII, but still flow through
  `attribute(_:_:context:)` so the context plumbing (URL allowlist, CSS) is unchanged.
- **`consuming` modifier chains** — every new modifier is `consuming … -> Self`, matching the CoW-bypass
  contract (ADR-0013).
- **The deployment floor stays macOS 15 / iOS 18.**
- **Additive only** — every typed modifier is an overload alongside the existing `String` one; no call
  site breaks.

## 6. Examples (before → after)

```swift
// Attributes (F1):
a { }.target("_blank").rel("noopener noreferrer")     →  a { }.target(.blank).rel(.noopener, .noreferrer)
input().type("email")                                  →  input().type(.email)
img().attribute("loading", "lazy")                     →  img().loading(.lazy)
div { }.role("navigation").aria("live", "polite")      →  div { }.role(.navigation).ariaLive(.polite)
input().attribute("required", "")                      →  input().required()

// Interactive component (F3/F4/F6):
Island("counter", scope: [countSignal.id]) {           →  Island("counter") {            // scope inferred
    button { "+" }.on("click", .increment(countSignal))      button { "+" }.on(.click, .increment(countSignal))
    span { String(count) }.bind(.text, to: countSignal.id)   span { String(count) }.bind(.text, to: countSignal)
}                                                       }
```

## 7. A whole app, across files (target DSL)

A small storefront as one SPM target (`Examples/Storefront`). Files in a target see each other with no
imports; each file just `import ADHTML`. This is the **target** DSL — implicit islands (no `Island`/
`scope`), `$state`, `@Derived`, typed attributes, and a slotted layout. It is what the compilable example
app converges to as §3.0/§3.5 land; the first committed example uses today's explicit-`Island` API.

```
Examples/Storefront/
├── Models.swift            // plain value types
├── Theme.swift             // typed style tokens / shared enums
├── Layout.swift            // PageLayout: a component WITH children (slot)
├── Components/
│   ├── ProductCard.swift   // static component (renders inline, no JS)
│   └── AddToCart.swift     // interactive component → implicit island
├── Pages/
│   └── CatalogPage.swift   // composes Layout + grid + interactive cart
└── main.swift              // render entry
```

```swift
// Models.swift
struct Product: Identifiable, Sendable {
    let id: String, name: String, price: Int, imageURL: String, inStock: Bool
}

// Layout.swift — a component that accepts children (the slot mechanism, §3.7)
struct PageLayout<Body: HTML>: Component {
    let pageTitle: String
    @HTMLBuilder let content: Body          // the slot
    var body: some HTML {
        html {
            head {
                meta.charset(.utf8)                       // §3.6 conveniences
                meta.viewport()
                title { pageTitle }
                Stylesheet("/app.css")
            }
            body {
                nav {
                    a { "Acme" }.href("/").class("brand")
                    a { "Cart" }.href("/cart")
                }.role(.navigation)                       // typed ARIA (§3.1)
                main { content }                          // children rendered here
                footer { p { "© 2026 Acme" } }
            }
        }.lang("en")
    }
}

// Components/ProductCard.swift — static: no @State ⇒ renders inline, ships no JS
struct ProductCard: Component {
    let product: Product
    var body: some HTML {
        article {
            img().src(product.imageURL).alt(product.name).loading(.lazy)   // typed enum (§3.1)
            h3 { product.name }
            p { "$\(product.price)" }.class("price")
            if product.inStock {
                AddToCart(productID: product.id)          // nested interactive component
            } else {
                span { "Sold out" }.class("muted")
            }
        }.class("card")
    }
}

// Components/AddToCart.swift — interactive ⇒ IMPLICIT ISLAND (no Island/scope/.id, §3.0)
struct AddToCart: Component {
    let productID: String
    @State var quantity = 0
    @Derived var inCart = $quantity > 0                   // computed/derived (§3.0b/§3.5)

    var body: some HTML {
        div {
            button { "−" }.on(.click, .increment($quantity, by: -1))   // typed event + $state
            span { }.bind(.text, to: $quantity)                        // initial value auto-filled (§3.3)
            button { "+" }.on(.click, .increment($quantity))
            button { "Add" }.bind(.disabled, to: !$inCart)             // derived drives the DOM
        }.class("add-to-cart").data("product", productID)
    }
}

// Pages/CatalogPage.swift — composition; the page is just data + components
struct CatalogPage: Component {
    let products: [Product]
    var body: some HTML {
        PageLayout(pageTitle: "Shop — Acme") {            // layout via the slot
            h1 { "Shop" }
            div { for product in products { ProductCard(product: product) } }.class("grid")
        }
    }
}

// main.swift — one render call; the framework emits islands + the inline state for the
// interactive components automatically (no per-island bookkeeping in app code).
let products = ProductRepository.all()
let html = try HTMLDocument { CatalogPage(products: products) }.renderHydratable()
print(html)
```

The developer wrote **zero** `Island`, **zero** `scope:`, **zero** `.id` — yet each `AddToCart` instance
becomes its own resumable island with an inferred scope, and `ProductCard`/`PageLayout` stay static and
ship no JS. That is the SwiftUI-grade target: think in components and state; the engine handles SSR,
islands, and the wire.

## 8. References

- RFC-0003 (reactivity/hydration), RFC-0004 (whole-scope compile), ADR-0005/0008/0009/0013.
- WHATWG HTML — attribute value enumerations; WAI-ARIA 1.2 — roles and states/properties.
