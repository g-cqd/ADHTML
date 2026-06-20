// The render target abstraction (RFC-0002 / ADR-0002, refined for performance). Lowering an `HTML` tree
// emits a sequence of render tokens (open tag, attribute, text, close tag, island boundary). A
// `RenderTarget` receives those tokens; there are two implementations:
//
//   • `DirectTarget` writes the bytes STRAIGHT to a sink in a single pass — the fast path for
//     `render()`/`renderBytes()` (no intermediate buffer, no per-token allocation, fully specialized +
//     inlined for the static view tree).
//   • `HTMLProgram` (Render/HTMLOp.swift) records the tokens as a flat opcode array — the path that
//     needs a materialized program: the `maxDepth` failure-safe guard, hydration island-collection +
//     state serialization, and chunked streaming. Its emit walk stays iterative (stack-safe).
//
// Both go through the one set of byte-writers below (`HTMLBytes`), so the wire output is identical and the
// byte logic lives in exactly one place.

/// Receives the render tokens produced by lowering an ``HTML`` tree. See `DirectTarget` / `HTMLProgram`.
public protocol RenderTarget {
    mutating func openTagStart(_ name: StaticString)
    mutating func attribute(name: String, value: String, context: EscapeContext)
    mutating func openTagEnd()
    mutating func voidTagEnd()
    mutating func text(_ value: String)
    mutating func raw(_ bytes: [UInt8])
    mutating func closeTag(_ name: StaticString)
    mutating func islandOpen(id: IslandID, on: LoadStrategy, scope: [CellID], connect: String?, key: String?)
    mutating func islandClose()
}

/// The single source of HTML byte output, shared by `DirectTarget` and the opcode emit (`Renderer`).
@usableFromInline
enum HTMLBytes {
    @inlinable @inline(__always)
    static func openTagStart(_ markup: StaticString, into sink: inout some HTMLByteSink) {
        sink.writeStatic(markup)  // "<tag" (precomputed, includes the leading '<')
    }
    @inlinable @inline(__always)
    static func attribute(
        name: String, value: String, context: EscapeContext, into sink: inout some HTMLByteSink
    ) {
        sink.writeByte(0x20)  // space
        sink.writeUTF8(name)
        sink.writeByte(0x3D)  // =
        sink.writeByte(0x22)  // "
        Escaper.write(value, context: context, into: &sink)
        sink.writeByte(0x22)  // "
    }
    @inlinable @inline(__always)
    static func tagEnd(into sink: inout some HTMLByteSink) { sink.writeByte(0x3E) }  // >
    @inlinable @inline(__always)
    static func text(_ value: String, into sink: inout some HTMLByteSink) {
        Escaper.write(value, context: .text, into: &sink)
    }
    @inlinable @inline(__always)
    static func raw(_ bytes: [UInt8], into sink: inout some HTMLByteSink) { sink.write(bytes) }
    @inlinable @inline(__always)
    static func closeTag(_ markup: StaticString, into sink: inout some HTMLByteSink) {
        sink.writeStatic(markup)  // "</tag>" (precomputed)
    }
    @inlinable @inline(__always)
    static func islandOpen(
        id: IslandID, on: LoadStrategy, connect: String?, key: String?, into sink: inout some HTMLByteSink
    ) {
        sink.writeStatic("<div data-a")
        if let key {  // a Region's stable plain `id` — a getElementById morph target; absent ⇒ unchanged bytes
            sink.writeStatic(" id=\"")
            Escaper.write(key, context: .attribute, into: &sink)
            sink.writeStatic("\"")
        }
        sink.writeStatic(" data-b=\"")
        Escaper.write(id.raw, context: .attribute, into: &sink)
        sink.writeStatic("\" data-c=\"")
        Escaper.write(on.attributeValue, context: .attribute, into: &sink)
        if let connect {  // declarative SSE subscription (RFC-0019 §6.3-H); absent ⇒ byte-identical to before
            sink.writeStatic("\" data-d=\"")
            Escaper.write(connect, context: .attribute, into: &sink)
        }
        sink.writeStatic("\">")
    }
    @inlinable @inline(__always)
    static func islandClose(into sink: inout some HTMLByteSink) { sink.writeStatic("</div>") }
}

/// A `RenderTarget` that writes bytes straight to a sink — the single-pass fast path. The whole lowering
/// monomorphizes + inlines for the concrete view tree, so there is no opcode buffer and no per-token
/// allocation.
public struct DirectTarget<Sink: HTMLByteSink>: RenderTarget {
    @usableFromInline var sink: Sink

    @inlinable public init(sink: Sink) { self.sink = sink }

    @inlinable public mutating func openTagStart(_ name: StaticString) {
        HTMLBytes.openTagStart(name, into: &sink)
    }
    @inlinable public mutating func attribute(name: String, value: String, context: EscapeContext) {
        HTMLBytes.attribute(name: name, value: value, context: context, into: &sink)
    }
    @inlinable public mutating func openTagEnd() { HTMLBytes.tagEnd(into: &sink) }
    @inlinable public mutating func voidTagEnd() { HTMLBytes.tagEnd(into: &sink) }
    @inlinable public mutating func text(_ value: String) { HTMLBytes.text(value, into: &sink) }
    @inlinable public mutating func raw(_ bytes: [UInt8]) { HTMLBytes.raw(bytes, into: &sink) }
    @inlinable public mutating func closeTag(_ name: StaticString) {
        HTMLBytes.closeTag(name, into: &sink)
    }
    @inlinable public mutating func islandOpen(
        id: IslandID, on: LoadStrategy, scope: [CellID], connect: String?, key: String?
    ) {
        HTMLBytes.islandOpen(id: id, on: on, connect: connect, key: key, into: &sink)
    }
    @inlinable public mutating func islandClose() { HTMLBytes.islandClose(into: &sink) }
}
