# Reactivity & the Hydration Wire

Serializable signals, the closed client-recomputable expression DSL, and how a render becomes resumable
interactive markup.

## Overview

ADHTML's host is Swift (NIO), which cannot run JavaScript server-side. So the server renders HTML *once* and
ships **state plus a small generic runtime** for the client — never a second copy of the view logic. The
reactive layer is built for that single render: it evaluates each cell's value for the initial HTML and
records the dependency graph for serialization. The push-pull propagation loop runs entirely in the browser.

## Signals & computeds

A ``Signal`` is a `Sendable` value-type handle into a ``CellArena``. It carries a typed value (the
server-render default) and a stable ``CellID``; the arena records the cell for serialization.

```swift
let arena = CellArena()
let count = arena.signal(0)        // Signal<Int>
count.value                        // 0 — reads inside a computed record a dependency edge
```

A ``Computed`` is a derived cell. It is evaluated once during the render pass; the cells read during that
evaluation become its recorded dependencies. There are two kinds:

- `arena.computed { … }` — wraps an **opaque** Swift closure. The client cannot re-run it, so its value is
  server-fixed (updated only by a live SSE patch).
- `arena.computed(_ reactive:)` — takes a ``Reactive`` built from the **closed operator DSL**. It is
  evaluated once for the initial value *and* serialized as a ``WireExpr`` the client re-evaluates reactively,
  so the derived value updates in-browser with no server round-trip.

## The closed expression DSL

``Reactive`` is a value-type operand: the ``WireExpr`` to serialize plus its server-evaluated value, so one
expression doubles as the initial value and the client formula. Build them from `.reactive` on a signal or
computed, from literals, and the operators:

```swift
let total = count.reactive * 2 + base.reactive      // Reactive<Int>
let inCart = qty.reactive > 0                        // Reactive<Bool>
let shown  = inCart && !hidden.reactive              // Reactive<Bool>
```

The operator set is intentionally small and **total** (no partial operations such as division in v1):

- arithmetic `+` `-` `*` and string concatenation (``BinaryOp``);
- comparisons `==` `!=` `<` `<=` `>` `>=` and boolean `&&` `||` `!`;
- string/collection helpers — `contains`, `filter`, `count`, `lowercased` (``UnaryOp``).

Each operator has a mirror in the client evaluator, and a parity test pins the two token sets in sync, so the
SSR value and the client recompute always agree. Adding an operator means adding a ``BinaryOp`` /
``UnaryOp`` case here and its client mirror together.

## Islands: the data-leak boundary

An ``Island`` is a resumable interactive region. Its `scope` is the set of ``CellID``s it owns — and that
scope is the **data-leak boundary**: the wire serializer emits *only* cells reachable from a declared island's
scope (plus their dependencies). A signal that no island scopes never reaches the client.

```swift
let secret = arena.signal("TOP_SECRET")    // not in any island scope → never serialized
let shown  = arena.signal(7)
Island("panel", scope: [shown.id]) { … }   // only `shown` (and its deps) reach the wire
```

In practice you rarely write `Island` by hand: the `@Component` macro auto-wraps an interactive component as
an island with an **inferred** scope (the cells the component touched), so the boundary is computed by the
engine rather than hand-listed. An island's ``LoadStrategy`` (`.load` / `.visible` / …) decides when the
runtime wires it.

## The wire format

`renderHydratable(arena:)` renders the body bytes and appends an inline state script carrying this render's
island-scoped reactive state:

```html
<script type="application/adh-state+json" id="adh-state">
{"v":1,"cells":[{"$":"sig","v":0},{"$":"cmp","d":[0],"v":0,"e":{"o":">","l":{"c":0},"r":{"i":0}}}],
 "islands":[{"id":"c1","on":"load","scope":[0,1]}]}
</script>
```

- `cells` are emitted in creation order, which is a topological order — a computed can only read cells created
  before it, so a dependency is just an earlier index, and references are compacted (re-indexed) to the
  reachable set.
- A `sig` cell carries its value `v`; a `cmp` cell carries its dependencies `d`, value `v`, and — when it was
  built from a ``Reactive`` — its formula `e` (the serialized ``WireExpr``), which the client re-evaluates.
- The payload is produced by ``WireSerializer`` and escaped for safe embedding in the inline script, so a
  hostile string value can never break out of the `<script>`.

The token vocabulary (``WireToken`` and friends) is generated from a single source shared with the client
runtime, so the renderer and the runtime can never drift.

## Resuming in the browser

The client runtime (~4.5 KiB gzip, hand-written — not Swift→WASM) reads the inline state, reconstructs the
cell graph, and wires each island per its load strategy with a single delegated listener per event type
(qwikloader-style). A bound element carries `data-adh-*` attributes that name the cell and the behavior; an
event runs a behavior → sets a signal → the bound nodes update. A `cmp` cell's `e` formula is re-evaluated in
the browser, so derived values stay live with no round-trip.

> Important: the reactive bookkeeping is *only* active on the hydratable path. A plain `render()` /
> `renderBytes()` installs no ambient context and pays zero reactive overhead — the static perimeter ships
> no state and no JS.

## Streaming

`renderHydratable(into:arena:)` streams the body bytes to an ``AsyncHTMLByteSink`` in chunks (for
time-to-first-byte and back-pressure), then writes the inline state script as the final chunk. The state is
serialized up front, so a serialization failure surfaces before any bytes flush. See ``AsyncRenderer``.
