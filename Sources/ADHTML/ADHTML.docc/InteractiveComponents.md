# Interactive Components

Build resumable UI with `@Component`, `@State`, and the binding vocabulary — no `Island`, `scope`, or `.id`.

## Overview

You make a view interactive by adding reactive state, not by managing a hydration boundary. A `@Component`
with any `@State` (or `@Bound`, see <doc:DerivedState>) becomes a hydration **island** automatically: the
macro infers the island's scope from the cells the component touches and wraps the body. You think in state
and views; the engine handles SSR, the island boundary, and the wire.

## State

`@State var count = 0` keeps `count` as the server-render default and adds a peer **`$count`** — the
`Signal` handle that bindings and behaviors target. Provide an explicit type or a literal
initializer so the signal type is known:

```swift
@State var count = 0           // Signal<Int>
@State var label: String = ""  // Signal<String>
@State var open: Bool = false  // Signal<Bool>
```

One piece of state is the value (`count`), and the handle is `<name>Signal` (`$count`).

## Events: `.on`

Wire a closed, typed client `Behavior` to a typed `DOMEvent`:

```swift
button { "+" }.on(.click, .increment($count))
button { "Toggle" }.on(.click, .toggle($open))
input().on(.input, .setFromValue($query))
```

The behavior set is a closed Swift `enum` (increment, toggle, set, …), so an event→state binding is checked
at compile time — there are no stringly-typed handlers. `.on("custom", …)` keeps the string escape hatch for
events outside the typed set.

## Value bindings: `.bind`

Bind a cell to an element's text, value, or class. The `BindTarget` is `.text` / `.value` /
`.class`:

```swift
span { String(count) }.bind(.text, to: $count)
input().bind(.value, to: $label)
div { }.bind(.class, to: $theme)
```

`.bind` accepts a `Signal`, a `Computed`, a `Reactive` expression
(see <doc:DerivedState>), or a raw `CellID`.

## Two-way binding: `.model`

```swift
input().model($name)   // typing updates the signal; a signal change updates the field
```

Emits the initial `value` (no flash) and wires both directions for `<input>` / `<textarea>`.

## Conditional class, visibility, and mounting

```swift
button { "Buy" }.classToggle("active", when: $inStock)   // merges; never clobbers static class
div { … }.show(when: $open)                              // toggles display; stays in the DOM
When($open) { aside { "Details" } }                      // mounts/unmounts (v-if-style)
```

`classToggle` and `show` paint the initial state into the server HTML, so there is no hydration flash;
`When` keeps its content in a `<template>` so it is absent (not just hidden) without JS.

## Keyboard refinements

```swift
input()
    .on(.keydown, Behavior.commitValue($items))
    .keys("Enter")              // fire only for these event.key values
    .preventDefault()
    .keymap([                   // map several keys to different behaviors on one element
        ("ArrowDown", Behavior.listMove($cursor, by: 1)),
        ("Enter", Behavior.commit($items)),
    ])
```

## When islands wire

An island's `LoadStrategy` decides *when* the runtime wires it. The default is `.load`;
override per component for lazy wiring:

```swift
@Component
struct Comments {
    @State var expanded = false
    static var hydration: LoadStrategy { .visible }   // wire when scrolled into view
    var body: some HTML { … }
}
```

A component with **no** reactive state renders inline — no island, no JS — so the static perimeter ships
nothing extra.

## Assembling a page

`Page` builds the document scaffold from a head slot and a content slot; ``HTMLDocument`` is the lower-level
wrapper it uses:

```swift
Page(head: {
    title { "Shop" }
    meta().attribute("charset", "utf-8")
}) {
    h1 { "Shop" }
    LikeButton()
}
```

## Rendering for a server

The hydratable path returns the markup plus the inline state script for the islands on the page:

```swift
let bytes = try view.renderHydratable(arena: CellArena())
```

With the gated `ADHTMLNIO` bridge, ADServe's `ResponseContent` gains `.adhtml(_:)` (buffered) and
`.adhtmlStream(_:)` (streamed, for time-to-first-byte) that call this for you.

## Server actions

For mutations that re-render a region from the server (with a no-JS form-POST fallback), the gated
`ADHTMLActions` product adds the `@Action` / `@Actions` macros — signed, typed, region-bound handlers
dispatched over a single endpoint. They complement the client behaviors here: behaviors update local signals;
actions run server logic and swap the result back in.
