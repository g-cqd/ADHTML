# The Rendering Model

How an ADHTML view lowers to bytes — the iterative opcode renderer, the two render targets, and
escape-by-default output encoding.

## Overview

ADHTML renders in two stages. First, a view *lowers* itself into a sequence of **render tokens** (open tag,
attribute, text, raw bytes, close tag, island boundary). Second, a target turns those tokens into HTML bytes.
Lowering is monomorphized over the concrete view type (zero `any`), and the walk that produces bytes is a
single `for` loop — never recursion over the value tree — so the native stack stays O(1) regardless of how
deeply the document nests.

## Lowering: the `HTML` protocol

``HTML`` is the base node type. Every conformer implements one static requirement:

```swift
static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target)
```

`_render` is SPI — you call `render()` / `renderBytes()`, never `_render` directly. Primitive nodes
(``Text``, ``RawHTML``, the generated elements) implement it; composed views conform to ``Component`` and get
it for free, lowering their `@HTMLBuilder var body` in place.

Because `_render` is generic over `Target` (not an existential), a heterogeneous `[any HTML]` cannot be
rendered — control flow in a builder uses the compiler-synthesized `_HTMLEither` / `buildOptional` instead, so
the view tree stays fully typed and the lowering stays specialized.

## Two render targets

``RenderTarget`` receives the render tokens. There are two conformers, chosen by the entry point:

- ``DirectTarget`` writes bytes **straight to a sink** in a single pass — the fast path for `render()` /
  `renderBytes()`. There is no intermediate buffer and no per-token allocation; the whole static view tree
  specializes and inlines.
- ``HTMLProgram`` records each token as an opcode in a flat contiguous array — the **materialized** path
  used when the renderer needs to walk the program more than once: the `maxDepth` failure-safe ceiling,
  hydration island collection + state serialization, and chunked streaming.

Both funnel through one set of byte writers, so the output bytes are identical regardless of path.

## Render entry points

```swift
let string = view.render()                       // String
let bytes  = view.renderBytes()                  // [UInt8] — single-pass, no depth ceiling
let bytes  = try view.renderBytes(maxDepth: 512) // throws RenderError on adversarial nesting
```

- `render()` / `renderBytes()` are the **static** path: no hydration, no reactive bookkeeping, the fastest
  output. Use them for the no-island perimeter (the bulk of most pages).
- `renderBytes(maxDepth:)` and the hydratable path (see <doc:Reactivity>) use the materialized ``HTMLProgram``
  so an open-tag-depth ceiling can be enforced during the iterative emit. It throws ``RenderError`` rather
  than emitting unbounded output — a failure-safe contract for programs built from dynamic data. The walk is
  non-recursive, so it can never overflow the stack; the ceiling bounds pathological *work*.

> Note: ``Renderer`` exposes the depth-bounded program walk directly when you already hold an ``HTMLProgram``.
> ``AsyncRenderer`` streams a program's bytes to an ``AsyncHTMLByteSink`` in chunks with back-pressure — see
> <doc:Reactivity> for the hydratable streaming entry.

## Escape-by-default

Output encoding is **escape-by-default and context-aware**. A bare `String` in a builder block becomes a
``Text`` node, escaped at emit time for the text context. Attribute values, URLs, and CSS each route through
``Escaper`` in their own ``EscapeContext``:

| Context | Used for | Neutralizes |
|---|---|---|
| `.text` | element content | `&` `<` `>` |
| `.attribute` | attribute values | `&` `<` `>` `"` `'` |
| `.url` | `href` / `src` destinations | dangerous schemes (``URLScheme`` allowlist) + escaping |

The URL context is allowlist-based: `javascript:`, `data:`, and `vbscript:` destinations are neutralized
before they can reach the DOM, so a user-supplied link can never become a script.

```swift
a { "profile" }.href(userInput)   // the destination is scheme-checked + escaped
span { userInput }                // escaped as text — `<script>` becomes &lt;script&gt;
```

## The one unescaped path

``RawHTML`` is the **single, conspicuously named, greppable bypass** — the only way bytes reach the output
unescaped. The caller asserts the bytes are already safe HTML; misuse is an XSS vector, so it is excluded from
no security audit. Grep `RawHTML` to enumerate every unescaped insertion in a codebase.

```swift
RawHTML(unsafelyEscaped: "<svg>…</svg>")   // trusted bytes only
```

## Why iterative

A recursive renderer's stack depth grows with document nesting, so adversarial or generated input can
overflow the native stack — a denial-of-service vector. ADHTML's emit walk is an explicit loop over the flat
opcode array, so depth is bounded by an integer ceiling you control, not by the call stack. This is the same
no-recursion discipline the parser and the wire serializer follow.
