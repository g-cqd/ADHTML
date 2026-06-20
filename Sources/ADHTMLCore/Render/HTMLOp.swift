// The flat opcode program (RFC-0002). Lowering appends `HTMLOp`s to a contiguous buffer; the renderer
// walks that buffer with a single loop — so the render walk has no recursion and a flat, cache-friendly
// access pattern, regardless of how deeply the *type-level* element tree nests.

/// One render instruction. The element tree lowers to a sequence of these.
public enum HTMLOp: Sendable {
    /// `<name` — the start of an open tag (attributes follow).
    case openTagStart(StaticString)
    /// ` name="value"` — an attribute, emitted in `context`.
    case attribute(name: String, value: String, context: EscapeContext)
    /// `>` — closes an open tag that has children.
    case openTagEnd
    /// `>` — closes a void element's open tag (no children, no closing tag).
    case voidTagEnd
    /// Escaped text content (emitted in the `.text` context).
    case text(String)
    /// Pre-escaped bytes emitted verbatim (the ``RawHTML`` hatch).
    case raw([UInt8])
    /// `</name>` — a closing tag.
    case closeTag(StaticString)
    /// Opens a hydration island root: `<div data-adh-island data-adh-id="…" data-adh-on="…">`, plus an
    /// optional `data-adh-connect="…"` when the island subscribes to a live SSE stream (RFC-0019 §6.3-H).
    /// The `scope` (cells reachable for this island) is read by the wire serializer, not the byte emit.
    /// `key` (non-`nil` for a ``Region``) additionally stamps a plain `id="…"` so the island is a
    /// `getElementById` morph target — what the RFC-0019 action interpreter resolves a target by. `nil`
    /// for an implicit/explicit ``Island`` (byte-identical to before — no plain `id`).
    case islandOpen(id: IslandID, on: LoadStrategy, scope: [CellID], connect: String?, key: String?)
    /// Closes a hydration island root (`</div>`).
    case islandClose
}

/// A flat, ordered list of ``HTMLOp``s produced by lowering an ``HTML`` tree. Walked iteratively by
/// ``Renderer``. As a ``RenderTarget`` it records each render token as an opcode — the materialized path
/// for `maxDepth`, hydration island-collection, and streaming (`render()`/`renderBytes()` use the
/// single-pass `DirectTarget` instead).
public struct HTMLProgram: Sendable {
    public private(set) var ops: ContiguousArray<HTMLOp> = []
    public init() {}
    /// Append one opcode. Used by ``HTMLProgram``'s ``RenderTarget`` conformance.
    public mutating func append(_ op: HTMLOp) { ops.append(op) }
}

extension HTMLProgram: RenderTarget {
    @inlinable public mutating func openTagStart(_ name: StaticString) { append(.openTagStart(name)) }
    @inlinable public mutating func attribute(name: String, value: String, context: EscapeContext) {
        append(.attribute(name: name, value: value, context: context))
    }
    @inlinable public mutating func openTagEnd() { append(.openTagEnd) }
    @inlinable public mutating func voidTagEnd() { append(.voidTagEnd) }
    @inlinable public mutating func text(_ value: String) { append(.text(value)) }
    @inlinable public mutating func raw(_ bytes: [UInt8]) { append(.raw(bytes)) }
    @inlinable public mutating func closeTag(_ name: StaticString) { append(.closeTag(name)) }
    @inlinable public mutating func islandOpen(
        id: IslandID, on: LoadStrategy, scope: [CellID], connect: String?, key: String?
    ) {
        append(.islandOpen(id: id, on: on, scope: scope, connect: connect, key: key))
    }
    @inlinable public mutating func islandClose() { append(.islandClose) }

    /// Full island fidelity (overrides the buffered default): render the slot's ops STRAIGHT INTO this
    /// program, so an embedded `Markdown` component's `islandOpen`/`islandClose` + its registered cells
    /// land in the page program exactly as if placed directly in the body — the hydration scan finds them
    /// unchanged. (The `direct` byte thunk is unused on this path.)
    @inlinable public mutating func _embedMarkdownSlot(
        program: (inout HTMLProgram) -> Void, direct: (inout DirectTarget<ArraySink>) -> Void
    ) {
        program(&self)
    }
}
