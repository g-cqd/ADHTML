# RFC 0002 — The iterative rendering core & byte-sink contract

- **Status**: Proposed
- **Date**: 2026-06-19
- **Area**: Rendering core
- **Depends on**: `ADFCore` (`ByteBufferPool`, `ASCII`), `OrderedCollections`
- **Related**: RFC-0001, ADR-0002 (iterative renderer), ADR-0003 (escaping), ADR-0010 (packaging), ADR-0012 (ADServe byte sink)

## Summary

The render core turns a Swift result-builder tree of **phantom-typed elements** (zero `any`, ported
from Elementary) into bytes through a **single iterative loop over a flat opcode program** —
deliberately *not* the recursive tree-walk every existing Swift HTML library uses. This bounds native
stack growth to O(1), removes a deep-input stack-overflow denial-of-service, gives one place that
awaits the streaming sink, and yields a cache-friendly sequential emit. Output targets `[UInt8]` today
and a streaming `AsyncHTMLByteSink` (NIO `ByteBuffer` + `ByteBufferPool`) once ADServe ADR-0046 lands.

## 1. The problem: everyone recurses

Elementary, swift-html, Plot, and HTMLKit all render by recursion — each node's render calls its
children's render. With static generics that recursion is monomorphized (no heap AST, no `any`), but
it is still **call-stack depth ∝ DOM nesting depth**. Under `async` streaming, each level is an `async`
frame doing `await sink.write(...)`, so a deep page is a long continuation chain — more frame setup,
harder to flatten across `await`, and a stack-depth ceiling for pathological or user-generated nesting
(a comment tree, a deeply nested data structure). For a server, unbounded client-influenced recursion
depth is a **failure-safety** problem (CWE-674, uncontrolled recursion).

## 2. The model

Three stages, only the last of which touches bytes:

1. **Type-level tree (compile time).** Elements are `HTMLElement<Tag: HTMLTag, Content: HTML>` with a
   phantom `Tag`; composition is SwiftUI-style (`struct View: HTML { var content: some HTML { … } }`).
   The result builder (`@HTMLBuilder`, using `buildPartialBlock` for unbounded arity with zero `any`)
   produces a concrete, monomorphized type. This is Elementary's proven model — we keep it.
2. **Lowering to a flat opcode program.** `static func _render(_ value: borrowing Self, into program:
   inout HTMLProgram)` appends `HTMLOp` values (`openTagStart`/`attribute`/`openTagEnd`/`voidTagEnd`/
   `text`/`raw`/`closeTag`, and later `islandBoundary`) to a `ContiguousArray`. The *type-level*
   structure is unrolled by the compiler; the **program is flat**.
3. **Iterative emit.** `Renderer.render` is a single `while`/`for` loop over `program.ops` that writes
   bytes to an `HTMLByteSink`. There is no recursion and exactly one `await` site in the async variant.

```swift
public enum HTMLOp: Sendable {
    case openTagStart(StaticString)        // "<div"
    case attribute(name: String, value: String)
    case openTagEnd                        // ">"
    case voidTagEnd                        // ">" for void elements (no close)
    case text(String)                      // escaped in .text context at emit time
    case raw([UInt8])                      // the one unescaped hatch (RawHTML)
    case closeTag(StaticString)            // "</div>"
}

public protocol HTMLByteSink {
    mutating func writeByte(_ byte: UInt8)
    mutating func write(_ bytes: UnsafeBufferPointer<UInt8>)
}
```

## 3. Complexity & safety

- **Time** O(n) in the number of nodes n (each op emitted once); escaping is O(b) in text bytes b.
- **Space** the opcode buffer is O(n) (a flat array; revisit with a streaming lowering for huge pages).
  Native call stack is **O(1)** — the win. Peak heap with the streaming sink is ~flat regardless of
  page size (flush on chunk boundary).
- **Failure-safe** the renderer tracks open-tag depth and throws `RenderError.maxDepthExceeded` past a
  configurable cap — a typed error, never a crash, on adversarial nesting. Cyclomatic complexity of the
  emit switch is bounded (SwiftLint `ignores_case_statements`).
- **Memory safety** byte writes go through `Span`/`UnsafeBufferPointer` with stated bounds; no escaping
  pointers; fuzzed (ADR-0003).

ADR-0002 also documents an explicit-`Deque` work-stack walk as the alternative for a *future dynamic
AST mode*; for the static-type model the flat opcode buffer already removes recursion, so `DequeModule`
is not a core dependency yet.

## 4. The byte-sink contract

- **Sync** `HTMLByteSink` (above) — the hot path; `ArraySink` collects into `[UInt8]`; `render() ->
  String` / `-> [UInt8]` are the fragment/test entry points (`consuming`).
- **Streaming** `AsyncHTMLByteSink { mutating func write(_ bytes: ArraySlice<UInt8>) async throws }` —
  Elementary-shaped, so a chunk flushes `<head>`/early markup while the body renders (TTFB win). The
  NIO adapter (`ADHTMLNIO`, gated) writes into a `ByteBuffer` drawn from `ADFCore.ByteBufferPool` and
  honors channel writability for back-pressure (ADR-0012). `AsyncForEach` streams read-model rows so a
  large page never fully materializes.

## 5. Concurrency & ownership

`.v6` language mode throughout. Node/attribute/op types are `Sendable` value types; `render` is
`consuming`; `_render` takes `borrowing Self`. No `any` on the hot path (parameter packs / partial
blocks keep nodes concrete). Shared renderer state (buffer pool) is guarded by `Synchronization.Mutex`.

## 6. Attribute model

Attributes are stored in an order-preserving `AttributeStore` (backed by `OrderedCollections`), so
output byte order is **deterministic** — required for stable ETags and island/cache IDs. `class` and
`style` **auto-merge** (space- and `;`-separated respectively); all other attributes overwrite. Merge
order is defined and tested.

## 7. Escaping handoff

Each `text`/`attribute` op carries (implicitly, by op kind and attribute type) its `EscapeContext`;
the emit loop routes every byte through the context-aware `Escaper` (ADR-0003). Text in body position
is always `.text`; an attribute value always `.attribute`; an `href` always `.url`. The author cannot
place unescaped bytes except via `RawHTML`.

## 8. Verification

- Golden tests for canonical output (`div { "a&b" }.class("x")` → `<div class="x">a&amp;b</div>`),
  void elements (`<br>` emits no close), attribute merge order.
- A `maxDepth` fail-safe test: a program past the cap throws, never overflows the stack.
- ordo-one benchmarks: render throughput (MB/s), allocations, p50/p90/p99 for a deep page and a wide
  1k-row list; `ADHTMLProbe` attributes CPU/instructions/footprint per phase (build → lower → emit).
- ASan/UBSan over the byte paths.

## References

[Elementary rendering](https://github.com/elementary-swift/elementary/blob/main/Sources/Elementary/Html+Rendering.swift) ·
[`Span` (Swift stdlib)](https://developer.apple.com/documentation/swift/span) ·
[CWE-674 Uncontrolled Recursion](https://cwe.mitre.org/data/definitions/674.html) ·
[swift-collections](https://github.com/apple/swift-collections).
