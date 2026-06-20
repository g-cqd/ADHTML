// The iterative renderer (RFC-0002 / ADR-0002): a single `for` loop over the flat opcode program,
// emitting bytes through an ``HTMLByteSink``. No recursion over the value tree — native stack is O(1),
// so deeply-nested input cannot overflow the stack. `render(_:into:maxDepth:)` adds a configurable
// open-tag-depth ceiling that throws (never crashes) on adversarial nesting — the failure-safe path
// for programs built from untrusted/dynamic data.

/// An error from the depth-bounded render path.
public enum RenderError: Error, Sendable, Equatable {
    /// Open-tag nesting exceeded the configured `maxDepth` ceiling.
    case maxDepthExceeded(Int)
}

/// Walks an ``HTMLProgram`` and writes HTML bytes. Stateless; the walk is iterative.
public enum Renderer {
    /// The default open-tag-depth ceiling for the dynamic/untrusted render paths (e.g.
    /// ``HTML/renderHydratable(arena:maxDepth:)``). Far beyond any real document nesting (browsers
    /// themselves cap around a few hundred), so it rejects only adversarial input. The non-recursive
    /// emit can't overflow the stack regardless; this bounds pathological output as defense-in-depth.
    public static let defaultMaxDepth = 512

    /// Emit `program` into `sink`. No depth ceiling — for trusted, statically-built views.
    public static func render(_ program: borrowing HTMLProgram, into sink: inout some HTMLByteSink) {
        for op in program.ops { emit(op, into: &sink) }
    }

    /// Emit `program` into `sink`, throwing ``RenderError/maxDepthExceeded(_:)`` if open-tag nesting
    /// exceeds `maxDepth`. The failure-safe path for dynamically-built programs.
    public static func render(
        _ program: borrowing HTMLProgram, into sink: inout some HTMLByteSink, maxDepth: Int
    ) throws(RenderError) {
        var depth = 0
        for op in program.ops {
            switch op {
                case .openTagStart, .islandOpen:
                    depth += 1
                    if depth > maxDepth { throw RenderError.maxDepthExceeded(maxDepth) }
                case .voidTagEnd, .closeTag, .islandClose:
                    depth -= 1
                default:
                    break
            }
            emit(op, into: &sink)
        }
    }

    /// Emit one opcode through the shared byte-writers (`HTMLBytes`) — the program-replay path
    /// (`maxDepth`, hydration, streaming). `render()`/`renderBytes()` bypass opcodes entirely via
    /// `DirectTarget`.
    static func emit(_ op: HTMLOp, into sink: inout some HTMLByteSink) {
        switch op {
            case .openTagStart(let name): HTMLBytes.openTagStart(name, into: &sink)
            case .attribute(let name, let value, let context):
                HTMLBytes.attribute(name: name, value: value, context: context, into: &sink)
            case .openTagEnd, .voidTagEnd: HTMLBytes.tagEnd(into: &sink)
            case .text(let value): HTMLBytes.text(value, into: &sink)
            case .raw(let bytes): HTMLBytes.raw(bytes, into: &sink)
            case .closeTag(let name): HTMLBytes.closeTag(name, into: &sink)
            case .islandOpen(let id, let on, _, let connect, let key):
                HTMLBytes.islandOpen(id: id, on: on, connect: connect, key: key, into: &sink)
            case .islandClose: HTMLBytes.islandClose(into: &sink)
        }
    }
}

extension HTML {
    /// Render to bytes (`text/html` UTF-8) in a SINGLE pass — lowering writes straight to the byte buffer
    /// via `DirectTarget`, with no intermediate opcode program. The whole static view tree specializes +
    /// inlines, so this is the fast path. No depth ceiling (the static DSL is type-bounded in depth).
    @inlinable
    public consuming func renderBytes() -> [UInt8] {
        var target = DirectTarget(sink: ArraySink(reservingCapacity: 512))
        Self._render(self, into: &target)
        return target.sink.bytes
    }

    /// Render to a `String`.
    @inlinable
    public consuming func render() -> String {
        String(decoding: self.renderBytes(), as: UTF8.self)
    }

    /// Render to bytes with an open-tag-depth ceiling; throws on adversarial nesting (failure-safe). Uses
    /// the materialized opcode path (`HTMLProgram`) so the ceiling is enforced during the iterative emit.
    public consuming func renderBytes(maxDepth: Int) throws(RenderError) -> [UInt8] {
        var program = HTMLProgram()
        Self._render(self, into: &program)
        var sink = ArraySink(reservingCapacity: program.ops.count * 16)
        try Renderer.render(program, into: &sink, maxDepth: maxDepth)
        return sink.bytes
    }
}
