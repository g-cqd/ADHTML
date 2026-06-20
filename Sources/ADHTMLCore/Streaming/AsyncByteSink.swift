private import Synchronization

// The streaming byte-sink contract (RFC-0002 / ADR-0012). A streaming render lowers the view to the
// flat opcode program (sync, cheap) and then pushes the BYTES out in chunks through an
// `AsyncHTMLByteSink`, so a network transport can flush `<head>` before the whole page is serialized
// (TTFB) and a slow client throttles the render through the sink's back-pressure (the `await` on
// `write` is the back-pressure point). Reference semantics + a `Sendable` requirement (not `inout`):
// exclusive access to an `inout` sink cannot be held across an `await`, so the sink owns its mutable
// state behind a reference. A typed `Failure` keeps the render path within the family's typed-throws
// discipline (`Never` for an in-memory sink; a transport error type for a NIO sink).
//
// NOTE — data-driven async streaming (an `AsyncForEach` over an `AsyncSequence`, rendered element by
// element so a huge collection never materializes the whole program) is intentionally deferred: the
// opcode buffer is a `Sendable` value type and cannot carry per-element async producers without either
// boxing closures into the opcode enum (breaking `Sendable`/value semantics) or a parallel async
// lowering hierarchy. This primitive streams the BYTES of a fully-lowered program — which is what the
// NIO bridge (Phase 5) needs — and the data-driven variant is a separate, additive design (ADR-0012).

/// A destination for streamed HTML bytes. Conformers are reference types so the renderer never holds an
/// `inout` across an `await`; `write` is the back-pressure point for a network transport.
public protocol AsyncHTMLByteSink: Sendable {
    /// The error a write can fail with — `Never` for an in-memory sink.
    associatedtype Failure: Error = Never
    /// Append a chunk of already-rendered bytes, suspending for back-pressure as needed.
    func write(_ bytes: [UInt8]) async throws(Failure)
}

/// An in-memory `AsyncHTMLByteSink` that accumulates everything written — the headless test/utility
/// target for the streaming renderer (the streamed bytes must equal the buffered `renderBytes()`).
/// `Sendable` via an internal `Mutex`, so it is safe to share across the render's suspension points.
public final class AsyncByteCollector: AsyncHTMLByteSink {
    public typealias Failure = Never

    private let storage = Mutex<[UInt8]>([])

    public init() {}

    public func write(_ chunk: [UInt8]) async {
        storage.withLock { $0.append(contentsOf: chunk) }
    }

    /// Everything written so far.
    public var bytes: [UInt8] { storage.withLock { $0 } }
}
