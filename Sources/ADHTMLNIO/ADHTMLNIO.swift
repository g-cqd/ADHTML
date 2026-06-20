// ADHTMLNIO (gated `ADHTML_NIO`) — the ADServe transport bridge (ADR-0012, RFC-0007 §3). ADServe already
// ships the transport primitives (`.html` / `.stream` / `.sse` / `Static` / `CSPNonce`); this module is
// the thin ADHTML-side forwarder. ADServe's `ResponseBodyWriter.write(_ [UInt8])` was shaped to match
// ADHTML's `AsyncHTMLByteSink.write(_:)` 1:1, so the sink adapter is a direct pass-through and the
// streaming bridge has no buffering/copy of its own.
public import ADHTMLCore
public import ADServeCore

/// Namespace for the NIO byte-sink + ADServe bridge (see ADR-0012).
public enum ADHTMLNIO {}

/// An `AsyncHTMLByteSink` that forwards every chunk to an ADServe `ResponseBodyWriter`. The render path
/// writes here; the bytes go straight onto the channel (back-pressure is the `await` inside the writer).
public final class ResponseBodyWriterSink: AsyncHTMLByteSink {
    public typealias Failure = any Error
    private let writer: any ResponseBodyWriter

    public init(_ writer: any ResponseBodyWriter) { self.writer = writer }

    public func write(_ bytes: [UInt8]) async throws { try await writer.write(bytes) }
}

extension ResponseContent {
    /// Render an ADHTML view to a **buffered** `text/html` response (body + the inline hydration state
    /// script for any islands). The whole page is materialized, then sent — use `adhtmlStream` for TTFB.
    public static func adhtml(_ view: consuming some HTML, arena: CellArena = CellArena())
        throws(WireError) -> ResponseContent
    {
        .html(try view.renderHydratable(arena: arena))
    }

    /// Render an ADHTML view as a **streamed** `text/html` response: `<head>` flushes before the body
    /// finishes (TTFB), the body streams in ~`chunkBytes` chunks with channel back-pressure, and the
    /// inline hydration state script is the final chunk. The state is serialized up front, so a wire
    /// failure surfaces before any bytes flush.
    public static func adhtmlStream<V: HTML>(
        _ view: V, arena: CellArena = CellArena(), chunkBytes: Int = 16 * 1024
    ) -> ResponseContent {
        .stream(contentType: MediaType.html.value) { writer in
            let node = view
            try await node.renderHydratable(
                into: ResponseBodyWriterSink(writer), arena: arena, chunkBytes: chunkBytes)
        }
    }

    /// Render a **static** (non-hydratable) ADHTML view as a streamed `text/html` response — no inline
    /// state script. For the static perimeter (the ~85% with no islands), where the runtime isn't needed.
    public static func adhtmlStaticStream<V: HTML>(_ view: V, chunkBytes: Int = 16 * 1024)
        -> ResponseContent
    {
        .stream(contentType: MediaType.html.value) { writer in
            let node = view
            try await node.render(into: ResponseBodyWriterSink(writer), chunkBytes: chunkBytes)
        }
    }
}

extension SSEWriter {
    /// Push a live out-of-band HTML swap to the client: render `view` (the island's new content) and emit
    /// a `morph` event the runtime reconciles into `[data-adh-id="<id>"]` (RFC-0003 §5). Drive it from a
    /// route's `.sse { writer in … }` body as the app's change feed produces updates.
    public func morph(id: IslandID, _ view: consuming some HTML) async throws {
        let frame = try WireSerializer.morphFrame(id: id, html: view.renderBytes())
        try await send(event: "morph", data: String(decoding: frame, as: UTF8.self), id: nil, retry: nil)
    }

    /// Push a fine-grained `patch` event: set wire cells (by their inline-state index) to new values — the
    /// runtime updates exactly the bound nodes, no re-render. (Index stability across renders is the
    /// stable-`CellID` follow-up; for now the caller supplies this render's wire indices.)
    public func patch(_ cells: [Int: WireValue]) async throws {
        let frame = try WireSerializer.patchFrame(cells)
        try await send(event: "patch", data: String(decoding: frame, as: UTF8.self), id: nil, retry: nil)
    }
}
