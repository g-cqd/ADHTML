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
    /// Emit `program` into `sink`. No depth ceiling — for trusted, statically-built views.
    public static func render(_ program: borrowing HTMLProgram, into sink: inout some HTMLByteSink) {
        for op in program.ops { emit(op, into: &sink) }
    }

    /// Emit `program` into `sink`, throwing ``RenderError/maxDepthExceeded(_:)`` if open-tag nesting
    /// exceeds `maxDepth`. The failure-safe path for dynamically-built programs.
    public static func render(
        _ program: borrowing HTMLProgram, into sink: inout some HTMLByteSink, maxDepth: Int
    ) throws {
        var depth = 0
        for op in program.ops {
            switch op {
                case .openTagStart:
                    depth += 1
                    if depth > maxDepth { throw RenderError.maxDepthExceeded(maxDepth) }
                case .voidTagEnd, .closeTag:
                    depth -= 1
                default:
                    break
            }
            emit(op, into: &sink)
        }
    }

    /// Emit one opcode. The shared byte-writing body of both render paths.
    private static func emit(_ op: HTMLOp, into sink: inout some HTMLByteSink) {
        switch op {
            case .openTagStart(let name):
                sink.writeByte(0x3C)  // <
                sink.writeStatic(name)
            case .attribute(let name, let value, let context):
                sink.writeByte(0x20)  // space
                sink.writeUTF8(name)
                sink.writeByte(0x3D)  // =
                sink.writeByte(0x22)  // "
                Escaper.write(value, context: context, into: &sink)
                sink.writeByte(0x22)  // "
            case .openTagEnd, .voidTagEnd:
                sink.writeByte(0x3E)  // >
            case .text(let value):
                Escaper.write(value, context: .text, into: &sink)
            case .raw(let bytes):
                sink.write(bytes)
            case .closeTag(let name):
                sink.writeByte(0x3C)  // <
                sink.writeByte(0x2F)  // /
                sink.writeStatic(name)
                sink.writeByte(0x3E)  // >
        }
    }
}

extension HTML {
    /// Render to bytes (`text/html` UTF-8). No depth ceiling — for trusted, statically-built views.
    public consuming func renderBytes() -> [UInt8] {
        var program = HTMLProgram()
        Self._render(self, into: &program)
        var sink = ArraySink(reservingCapacity: program.ops.count * 16)
        Renderer.render(program, into: &sink)
        return sink.bytes
    }

    /// Render to a `String`.
    public consuming func render() -> String {
        String(decoding: self.renderBytes(), as: UTF8.self)
    }

    /// Render to bytes with an open-tag-depth ceiling; throws on adversarial nesting (failure-safe).
    public consuming func renderBytes(maxDepth: Int) throws -> [UInt8] {
        var program = HTMLProgram()
        Self._render(self, into: &program)
        var sink = ArraySink(reservingCapacity: program.ops.count * 16)
        try Renderer.render(program, into: &sink, maxDepth: maxDepth)
        return sink.bytes
    }
}
