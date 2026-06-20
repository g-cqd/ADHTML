import Synchronization
import Testing

@testable import ADHTMLCore

// The streaming render path must produce byte-for-byte the same output as the buffered renderer — it is
// the same opcode emit, just flushed in chunks. These tests pin parity (plain + hydratable), that
// chunking actually happens, and that an empty view streams nothing.
@Suite("Streaming render")
struct StreamingTests {
    /// A sink that also counts `write` calls, to prove the renderer flushed in multiple chunks.
    final class CountingSink: AsyncHTMLByteSink {
        typealias Failure = Never
        private let state = Mutex<(bytes: [UInt8], writes: Int)>(([], 0))
        func write(_ chunk: [UInt8]) async {
            state.withLock {
                $0.bytes.append(contentsOf: chunk)
                $0.writes += 1
            }
        }
        var bytes: [UInt8] { state.withLock { $0.bytes } }
        var writes: Int { state.withLock { $0.writes } }
    }

    /// A 500-item list — large enough to span many small chunks.
    func bigList() -> some HTML {
        ul {
            for index in 0 ..< 500 { li { String(index) } }
        }
    }

    @Test("streamed bytes equal the buffered render")
    func parity() async {
        let buffered = bigList().renderBytes()
        let sink = AsyncByteCollector()
        await bigList().render(into: sink, chunkBytes: 64)
        #expect(sink.bytes == buffered)
    }

    @Test("a small chunk size produces many writes; a large one a single write")
    func chunking() async {
        let many = CountingSink()
        await bigList().render(into: many, chunkBytes: 64)
        #expect(many.writes > 1)

        let few = CountingSink()
        await bigList().render(into: few, chunkBytes: 1 << 20)
        #expect(few.writes == 1)
    }

    @Test("an empty view streams nothing")
    func empty() async {
        let sink = CountingSink()
        await EmptyHTML().render(into: sink)
        #expect(sink.bytes.isEmpty)
        #expect(sink.writes == 0)
    }

    @Test("streamed hydratable output equals the buffered hydratable output")
    func hydratableParity() async throws {
        let syncArena = CellArena()
        let buffered = try StreamCounter(count: 5).renderHydratable(arena: syncArena)

        let streamArena = CellArena()
        let sink = AsyncByteCollector()
        try await StreamCounter(count: 5).renderHydratable(into: sink, arena: streamArena, chunkBytes: 32)

        #expect(sink.bytes == buffered)
        #expect(streamArena.cells.count == 1)
    }
}

/// A minimal reactive component (the hand-written `@State` shape) for the hydratable streaming test.
private struct StreamCounter: Component {
    var count: Int = 0
    var countSignal: Signal<Int> { ADHTMLRenderContext.state(key: "count", default: count) }

    var body: some HTML {
        Island("sc", scope: [countSignal.id]) {
            span { String(count) }.bind(.text, to: countSignal.id)
        }
    }
}
