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
}

/// A flat, ordered list of ``HTMLOp``s produced by lowering an ``HTML`` tree. Walked iteratively by
/// ``Renderer``.
public struct HTMLProgram: Sendable {
    public private(set) var ops: ContiguousArray<HTMLOp> = []
    public init() {}
    /// Append one opcode. Used by ``HTML/_render(_:into:)`` implementations.
    public mutating func append(_ op: HTMLOp) { ops.append(op) }
}
