import ADHTMLCore
import ADHTMLNIO
import ADServeCore
import ADTestKit
import Testing

/// A `ResponseBodyWriter` that records each chunk into an ADTestKit `AsyncEventProbe`, so a test can
/// assert on the streamed chunk boundaries deterministically (no polling/sleep): `record` from any
/// isolation, `wait(forAtLeast:)` parks until the expected number of chunks has arrived.
final class ProbeBodyWriter: ResponseBodyWriter {
    let chunks = AsyncEventProbe<[UInt8]>()
    func write(_ chunk: [UInt8]) async throws { chunks.record(chunk) }
    func flush() async throws {}
}

struct BridgeTests {
    @Test
    func `the sink forwards a streamed render into a ResponseBodyWriter`() async throws {
        let writer = ProbeBodyWriter()
        try await div { "hi" }.render(into: ResponseBodyWriterSink(writer))
        let chunks = try await writer.chunks.wait(forAtLeast: 1)
        #expect(String(decoding: chunks.flatMap { $0 }, as: UTF8.self) == "<div>hi</div>")
    }

    @Test
    func `adhtml yields a buffered text/html response`() throws {
        let response = try ResponseContent.adhtml(div { span { "x" } })
        guard case .raw(let body, let contentType, _) = response else {
            Issue.record("expected .raw, got \(response)")
            return
        }
        #expect(contentType == "text/html; charset=utf-8")
        #expect(String(decoding: body, as: UTF8.self).hasPrefix("<div><span>x</span></div>"))
    }

    @Test
    func `adhtmlStaticStream chunks a large view and the bytes equal the buffered render`() async throws {
        func bigList() -> some HTML { ul { for index in 0 ..< 50 { li { "item \(index)" } } } }
        let expected = bigList().renderBytes()

        guard
            case .stream(let contentType, _, _, let body) =
                ResponseContent.adhtmlStaticStream(bigList(), chunkBytes: 16)
        else {
            Issue.record("expected .stream")
            return
        }
        #expect(contentType == "text/html; charset=utf-8")

        let writer = ProbeBodyWriter()
        try await body(writer)
        let chunks = try await writer.chunks.wait(forAtLeast: 2)  // it actually streamed in >1 chunk
        #expect(chunks.count >= 2)
        #expect(chunks.flatMap { $0 } == expected)  // streamed bytes == buffered render (no loss/reorder)
    }

    @Test
    func `adhtmlStream produces a hydratable text/html body through the bridge`() async throws {
        guard case .stream(let contentType, _, _, let body) = ResponseContent.adhtmlStream(div { "hi" })
        else {
            Issue.record("expected .stream")
            return
        }
        #expect(contentType == "text/html; charset=utf-8")
        let writer = ProbeBodyWriter()
        try await body(writer)
        let chunks = try await writer.chunks.wait(forAtLeast: 1)
        #expect(String(decoding: chunks.flatMap { $0 }, as: UTF8.self).hasPrefix("<div>hi</div>"))
    }
}
