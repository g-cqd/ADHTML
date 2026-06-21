# Derived State with `@Bound`

Declare a value computed from `@State` that re-evaluates in the browser — no server round-trip.

## Overview

`@Bound` declares a **client-recomputable** derived value. You write the formula once as a
`Reactive` expression over your signals; the engine evaluates it server-side for the initial
HTML *and* serializes it as a `WireExpr` the client re-evaluates whenever a dependency changes.
The derived value stays live in-browser with no fetch.

```swift
@Component
struct ProductRow {
    @State var qty = 0
    @Bound var inCart: Reactive<Bool> { qtySignal.reactive > 0 }

    var body: some HTML {
        div {
            button { "+" }.on(.click, Behavior.increment(qtySignal))
            span { String(qty) }.bind(.text, to: qtySignal)
            button { "Remove" }.show(when: inCartComputed)   // appears once qty > 0, live
        }
    }
}
```

## The handle: `<name>Computed`

The macro adds a peer **`inCartComputed`** of type `Computed` — the *registered* handle you
bind. It is what `BindTarget`-style bindings target:

```swift
span { … }.bind(.text, to: totalComputed)
div  { … }.show(when: inCartComputed)
When(inCartComputed) { … }
button { … }.classToggle("hot", when: isHotComputed)
```

`inCart` itself stays a plain computed property returning the raw `Reactive<Bool>`; `inCartComputed` is the
cell registered in the render arena.

## The expression DSL

The right-hand side is a `Reactive` value built from `.reactive` on your `@State` signals and
the closed operator set — arithmetic, comparisons, boolean logic, and string/collection helpers:

```swift
@Bound var total: Reactive<Int>    { applesSignal.reactive + orangesSignal.reactive }
@Bound var doubled: Reactive<Int>  { countSignal.reactive * 2 }
@Bound var visible: Reactive<Bool> { (qtySignal.reactive > 0) && !hiddenSignal.reactive }
```

String values compose too — a string literal is itself a `Reactive<String>`, so
`greetingSignal.reactive + "!"` concatenates on the client.

Every operator has a mirror in the client evaluator, so the server value and the in-browser recompute always
agree. The full operator set and the serialized wire format are covered by the `ADHTMLCore` reactivity
reference.

## Why the getter form

`@Bound` is written as a **getter** — `{ … }`, not `= …`. A derived value inherently references the
component's `@State` signal peers (`qtySignal`), and Swift forbids referencing an instance member in a
*stored-property* initializer. The getter runs when accessed, where `self` and the ambient render context
exist, so the reference is legal. The explicit `Reactive<T>` annotation is required (the value type `T` is
otherwise unknowable, and the macro needs it to emit `Computed<T>`).

## Bound-only components

A `@Bound` member makes its component an island just like `@State` does, so a component can be entirely
derived:

```swift
@Component
struct Badge {
    @Bound var label: Reactive<String> { /* from injected signals */ }
    var body: some HTML { span { … }.bind(.text, to: labelComputed) }
}
```

## Static rendering

On the static path (`render()` / `renderBytes()`, with no ambient context), a `@Bound` handle resolves
against a throwaway arena: the value renders inline with no wiring. So a `@Bound`-using component still
produces correct no-JS markup — it simply isn't wired for client recompute outside the hydratable path.
