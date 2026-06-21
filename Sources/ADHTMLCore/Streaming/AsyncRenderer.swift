// The streaming (async) render path (RFC-0002 / ADR-0012). It reuses the SAME iterative opcode emit as
// the buffered `Renderer` — the view is lowered once to the flat program, then walked in a single loop —
// but flushes the bytes to an `AsyncHTMLByteSink` in ~`chunkBytes` chunks, yielding between chunks. This
// gives a network transport TTFB (the `<head>` flushes before the page finishes serializing) and
// honours back-pressure (the `await` on `write` throttles a fast render to a slow client). Cancellation
// is cooperative: a cancelled task stops emitting at the next chunk boundary (failure-safe — a closing
// connection just stops receiving bytes). No recursion, O(1) native stack, like the sync path.

/// An error from the streaming hydratable render: either wire serialization failed, or the sink did.
public enum StreamRenderError<Failure: Error>: Error {
    /// The reactive state could not be serialized to the wire format.
    case wire(WireError)
    /// The sink failed while writing a chunk (e.g. the client disconnected).
    case sink(Failure)
}

extension StreamRenderError: Sendable where Failure: Sendable {}

/// Walks an ``HTMLProgram`` and streams its bytes to an ``AsyncHTMLByteSink``. Stateless; iterative.
public enum AsyncRenderer {
    /// Emit `program` into `sink` in ~`chunkBytes` chunks, yielding between chunks. Throws only what the
    /// sink throws (`Never` for an in-memory sink).
    public static func render<Sink: AsyncHTMLByteSink>(
        _ program: HTMLProgram, into sink: Sink, chunkBytes: Int = 16 * 1024
    ) async throws(Sink.Failure) {
        var buffer = ArraySink(reservingCapacity: Swift.min(chunkBytes, 1 << 16))
        for op in program.ops {
            Renderer.emit(op, into: &buffer)
            if buffer.bytes.count >= chunkBytes {
                if Task.isCancelled { return }  // cooperative stop — a closing connection wants no more
                try await sink.write(buffer.bytes)
                buffer.reset()
                await Task.yield()
            }
        }
        if !buffer.bytes.isEmpty {
            try await sink.write(buffer.bytes)
        }
    }
}

extension HTML {
    /// Stream this view's HTML bytes into `sink` in ~`chunkBytes` chunks (TTFB + back-pressure). The
    /// program is lowered in full first (cheap, in-memory opcodes); the BYTES stream out. Throws only
    /// what the sink throws.
    public consuming func render<Sink: AsyncHTMLByteSink>(
        into sink: Sink, chunkBytes: Int = 16 * 1024
    ) async throws(Sink.Failure) {
        var program = HTMLProgram()
        Self._render(self, into: &program)
        try await AsyncRenderer.render(program, into: sink, chunkBytes: chunkBytes)
    }

    /// Stream the hydratable document: the body bytes (chunked) followed by the inline
    /// `<script type="application/adh-state+json">` carrying this render's island-scoped reactive state.
    /// The state is serialized up front (so a `.wire` failure surfaces before any bytes flush); the body
    /// streams for TTFB, then the state script is written as the final chunk.
    public consuming func renderHydratable<Sink: AsyncHTMLByteSink>(
        into sink: Sink, arena: CellArena, chunkBytes: Int = 16 * 1024
    ) async throws(StreamRenderError<Sink.Failure>) {
        var program = HTMLProgram()
        let node = self
        let assets = AssetSink()
        let root = ADHTMLRenderContext.Context(arena: arena, scope: arena.freshScope(), assets: assets)
        ADHTMLRenderContext.$current.withValue(root) {
            Self._render(node, into: &program)
        }

        var islands: [WireIsland] = []
        for op in program.ops {
            if case .islandOpen(let id, let on, let scope, _, _) = op {
                // Re-derive a `@Component` island's scope post-render (includes nested non-island helper
                // cells); an explicit/Region island keeps its hand-listed `scope`.
                islands.append(WireIsland(id: id, on: on, scope: arena.derivedIslandScope(forID: id) ?? scope))
            }
        }

        let stateBytes: [UInt8]
        do {
            stateBytes = try WireSerializer.scriptBytes(cells: arena.cells, islands: islands)
        } catch {
            throw StreamRenderError.wire(error)
        }

        do {
            try await AsyncRenderer.render(program, into: sink, chunkBytes: chunkBytes)
            // Component-scoped assets (Track 4): the deduped `<style>` + inline `<script>`s precede the
            // state script in the tail.
            var tail = assets.styleTag()
            tail.append(contentsOf: assets.scriptTag())
            tail.append(contentsOf: Self.scriptOpen)
            tail.append(contentsOf: stateBytes)
            tail.append(contentsOf: Self.scriptClose)
            try await sink.write(tail)
        } catch {
            throw StreamRenderError.sink(error)
        }
    }
}
