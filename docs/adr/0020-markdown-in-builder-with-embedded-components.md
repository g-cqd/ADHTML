# ADR 0020 — Markdown in a component body, with embedded live components

- **Status**: Accepted
- **Date**: 2026-06-21
- **Related**: ADR-0003 (escape-by-default, context-aware), ADR-0002 (iterative renderer / `RenderTarget`),
  ADR-0005 (islands), ADR-0015 (implicit islands), RFC-0003 (wire format), the `ADHTMLMarkdown` renderer
  (gated `ADHTML_MARKDOWN`).

## Context

`ADHTMLMarkdown.render(_:linkResolver:allowRawHTML:) -> String` already turns a Markdown string into an
escape-by-default HTML fragment (it routes every text / attribute / URL value through ADHTMLCore's
`Escaper`, unlike swift-markdown's bundled `HTMLFormatter`). What it could not do is let an author write
Markdown **inside a component body** and embed **live ADHTML components** in the prose — a card, a buy
button, an interactive island — with the components fully rendered AND hydrated, not flattened to text.

Two things make that hard:

1. **Heterogeneous embedded components can't be `[any HTML]`.** `HTML._render<Target: RenderTarget>` is
   generic over its target (zero `any`, monomorphized — ADR-0002/0013). You cannot call a *static, generic*
   protocol requirement on an existential, so a `[any HTML]` list of embedded components could never be
   rendered.
2. **Hydration must be intact.** An embedded `@State`/`@Component` island has to enter the page exactly as
   if it were placed directly in the body — its `islandOpen`/`islandClose` + scoped cells must reach
   `renderHydratable`'s island scan and the wire serializer, unchanged.

## Decision

Add a gated `Markdown` `HTML` node with **two authoring surfaces** over one representation, a
**PUA-sentinel splice**, and a **target-generic render thunk** for each embedded slot.

### Two surfaces, one `MarkdownContent`

- **String form** — `Markdown(_ s: MarkdownString)`, where `MarkdownString` is
  `ExpressibleByStringInterpolation`. Literal segments are author-trusted Markdown; interpolations are
  typed: `\(component)` / `\(optional)` embed a live `some HTML` (no slot when nil); `\(text:)` is an
  UNTRUSTED string as escaped Markdown text (the safe default); `\(url:)` is a sanitized destination. There
  is deliberately **no** `appendInterpolation(_: String)` overload — a bare `\(string)` fails to compile (a
  `String` is not `HTML`), closing the injection footgun.
- **Builder form** — `Markdown { … }` with `@MarkdownBuilder`. Statements are author-trusted Markdown
  `String` fragments and `some HTML` components, with `if`/`else`/`for`/optional control flow
  (`buildOptional`/`buildEither`/`buildArray`). Fragments join with `\n`. This is what the string form
  cannot express: `Markdown { "# Title"; if hot { Badge("HOT") }; for x in xs { "- \(x.name)" } }`.

Both accumulate a `MarkdownContent` = a Markdown **source string with sentinels** + the **ordered slots**.

### The sentinel splice

A slot is planted in the Markdown source as a **Private-Use-Area scalar** `U+E000 + index`. The crux:
PUA scalars **survive `ADHTMLMarkdown.render`** — the `Escaper` rewrites only the five ASCII bytes
`& < > " '`, so a sentinel passes through the renderer untouched. `Markdown._render` then renders the
source ONCE, splits the resulting HTML on the sentinels, and interleaves `target.raw(segment)` with each
slot. Author text in `U+E000…U+F8FF` is sanitized to U+FFFD before sentinels are planted, so the only PUA
scalars in the source are the engine's own markers (6400-slot budget — the single PUA block).

### The target-generic render thunk (full island fidelity)

Each slot captures its concrete component `C` as **two closures** built by partial application of
`C._render` at the call site — `(inout HTMLProgram) -> Void` and `(inout DirectTarget<ArraySink>) -> Void`
— never `any HTML`. The single ADHTMLCore seam, `RenderTarget._embedMarkdownSlot(program:direct:)`,
dispatches type-safely:

- `HTMLProgram` (the hydration/streaming path) **overrides** the seam to render the slot's ops STRAIGHT
  INTO the page program. Because a `Component`'s `_render` writes its island ops onto whatever target it is
  handed, and the ambient `ADHTMLRenderContext` is still installed during `Markdown._render`, an embedded
  island's `islandOpen`/`islandClose` + registered cells land exactly where the existing island scan finds
  them — **zero change to `RenderHydratable` or the wire serializer**.
- Every byte target (`DirectTarget`, the static `render()` path) uses the **default**: buffer the slot via
  the `direct` thunk and emit it `raw`. Correct because the byte paths run no island scan — an embedded
  component renders inline, matching existing static semantics. (Streaming also lowers to `HTMLProgram`
  first, so those two are the only concrete targets.)

A lone block component (a slot alone in its paragraph) renders as `<p>…</p>`, which is invalid around a
block element; `_render` unwraps that exact `<p>SENTINEL</p>` shape. Delegated actions (`data-adh-*`) are
attribute-only, so they survive the splice and stay live on every path.

## The escaping proof

The only `raw` bytes emitted are (a) `ADHTMLMarkdown` renderer output — already escape-by-default — and
(b) embedded-component output — already produced by the engine (`Text` escapes; `RawHTML` is the single
audited bypass). Therefore:

- **A hostile Markdown string cannot break out around a slot.** The segments between sentinels are balanced,
  escaped renderer output; a slot is spliced at a sentinel boundary, never inside an attribute or tag.
- **Untrusted interpolation is contained.** `\(text:)` backslash-escapes Markdown metacharacters (literal
  text) and the renderer HTML-escapes `< > & " '`; `\(url:)` neutralizes destination-breaking characters
  and the renderer's `.url` context scheme-allowlists, so `[x](javascript:…)` is neutralized.
- **The sentinel never leaks.** Tested byte-for-byte: no `U+E000…U+F8FF` scalar appears in any output, and
  author-typed PUA scalars are sanitized so they cannot forge a slot.

## Consequences

- **Positive:** content-site authoring (Markdown prose) and app authoring (live components) compose in one
  body, with full hydration and no new XSS surface. The engine reuse is total — `ADHTMLMarkdown.swift` and
  the wire serializer are untouched; the entire feature is the gated `ADHTMLMarkdown` files plus one
  `RenderTarget` seam.
- **Negative / bounded:** a slot inside a code span/block is unsupported (P1); slot order assumes the
  renderer preserves source order (true for normal flow — each sentinel still carries its own index, so a
  reorder mis-places but never crashes); the 6400-slot PUA budget is a documented ceiling. List items
  inherit the renderer's existing `<li><p>…</p>` shape (not a Markdown-in-builder concern).
- **Invariants kept:** escape-by-default; zero `any` (the thunk, not an existential); the wire format and
  `RenderHydratable` unchanged; gated so the default graph never resolves swift-markdown.
