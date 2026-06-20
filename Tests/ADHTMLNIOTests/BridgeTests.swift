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

/// An `SSEWriter` test double that records each emitted event (name + data) for assertions.
final class ProbeSSEWriter: SSEWriter {
    struct SSEFrame: Sendable {
        let event: String?
        let data: String
    }
    let frames = AsyncEventProbe<SSEFrame>()
    func send(event: String?, data: String, id: String?, retry: Int?) async throws {
        frames.record(SSEFrame(event: event, data: data))
    }
    func comment(_ text: String) async throws {}
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
    func `view is the buffered full-page alias (RFC-0020 §1)`() throws {
        let response = try ResponseContent.view(div { span { "x" } })
        guard case .raw(let body, let contentType, _) = response else {
            Issue.record("expected .raw, got \(response)")
            return
        }
        #expect(contentType == "text/html; charset=utf-8")
        let html = String(decoding: body, as: UTF8.self)
        #expect(html.hasPrefix("<div><span>x</span></div>"))
        #expect(html.contains("adh-state"))  // full page carries the inline hydration state
    }

    @Test
    func `adhtmlFragment yields a partial text/html response (no doctype, no state script)`() {
        let response = ResponseContent.adhtmlFragment(ul { li { "row" } })
        guard case .raw(let body, let contentType, _) = response else {
            Issue.record("expected .raw, got \(response)")
            return
        }
        let html = String(decoding: body, as: UTF8.self)
        #expect(contentType == "text/html; charset=utf-8")
        #expect(html == "<ul><li>row</li></ul>")  // a partial: no <!doctype>/<html>, no inline adh-state
        #expect(!html.contains("adh-state"))
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

    @Test
    func `SSEWriter morph emits a morph event with the rendered fragment`() async throws {
        let writer = ProbeSSEWriter()
        try await writer.morph(id: "parts-rows", div { span { "new" } })
        let frames = try await writer.frames.wait(forAtLeast: 1)
        #expect(frames[0].event == "morph")
        #expect(frames[0].data == #"{"id":"parts-rows","html":"<div><span>new</span></div>"}"#)
    }

    @Test
    func `SSEWriter patch emits cells in ascending index order`() async throws {
        let writer = ProbeSSEWriter()
        try await writer.patch([1: .int(5), 0: .string("hi")])
        let frames = try await writer.frames.wait(forAtLeast: 1)
        #expect(frames[0].event == "patch")
        #expect(frames[0].data == #"{"cells":{"0":{"v":"hi"},"1":{"v":5}}}"#)
    }
}
