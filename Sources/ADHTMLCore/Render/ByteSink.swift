// The byte-sink contract (RFC-0002). The renderer writes through `HTMLByteSink`; `ArraySink` collects
// into `[UInt8]`. A streaming `AsyncHTMLByteSink` over NIO `ByteBuffer` is the gated `ADHTMLNIO`
// adapter (ADR-0012). Convenience writers (`writeStatic`/`writeUTF8`) are built on the two primitives.

/// A destination for rendered HTML bytes.
public protocol HTMLByteSink {
    /// Append a single byte.
    mutating func writeByte(_ byte: UInt8)
    /// Append a buffer of bytes.
    mutating func write(_ bytes: UnsafeBufferPointer<UInt8>)
}

extension HTMLByteSink {
    /// Append an array of bytes.
    @inlinable public mutating func write(_ bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { write($0) }
    }
    /// Append a static string's UTF-8 (entity literals, tag names).
    @inlinable public mutating func writeStatic(_ string: StaticString) {
        string.withUTF8Buffer { write($0) }
    }
    /// Append a string's UTF-8 verbatim (caller ensures it is already safe in context).
    @inlinable public mutating func writeUTF8(_ string: String) {
        var copy = string
        copy.withUTF8 { write($0) }
    }
}

/// A `[UInt8]`-backed sink — the fragment/test render target.
public struct ArraySink: HTMLByteSink {
    public private(set) var bytes: [UInt8]
    public init(reservingCapacity capacity: Int = 0) {
        bytes = []
        if capacity > 0 { bytes.reserveCapacity(capacity) }
    }
    public mutating func writeByte(_ byte: UInt8) { bytes.append(byte) }
    public mutating func write(_ buffer: UnsafeBufferPointer<UInt8>) {
        bytes.append(contentsOf: buffer)
    }
    /// Empty the buffer while keeping its allocation — lets the async renderer reuse one chunk buffer.
    public mutating func reset() { bytes.removeAll(keepingCapacity: true) }
}
