import Testing

@testable import ADHTMLCore

/// Adversarial output-encoding tests (ADR-0003). Output must be XSS-safe by construction: a value
/// placed in any context can never introduce live markup or a dangerous URL scheme.
struct XSSTests {
    static let vectors = [
        "<script>alert(1)</script>",
        #""><img src=x onerror=alert(1)>"#,
        "<svg/onload=alert(1)>",
        #"'><script>alert(1)</script>"#,
        "</span><script>alert(1)</script>"
    ]

    @Test(arguments: vectors)
    func `text-context vectors render inert`(_ vector: String) {
        let out = span { vector }.render()
        #expect(!out.contains("<script"))
        #expect(!out.contains("<img"))
        #expect(!out.contains("<svg"))
        #expect(out.contains("&lt;"))
    }

    @Test(arguments: vectors)
    func `attribute-context vectors cannot inject markup`(_ vector: String) {
        let out = div {}.attribute("title", vector).render()
        #expect(!out.contains("<script"))
        #expect(!out.contains("<img"))
        #expect(!out.contains("<svg"))
        #expect(out.contains("&quot;") || !vector.contains("\""))
    }

    @Test
    func `dangerous href schemes are neutralized to an inert placeholder`() {
        let bad = [
            "javascript:alert(1)",
            "JaVaScRiPt:alert(1)",
            " javascript:alert(1)",
            "\tjavascript:alert(1)",
            "data:text/html,<script>alert(1)</script>",
            "vbscript:msgbox(1)"
        ]
        for url in bad {
            #expect(a { "x" }.href(url).render() == ##"<a href="#">x</a>"##)
        }
    }

    @Test
    func `safe href schemes and relative URLs pass through`() {
        #expect(a { "x" }.href("https://example.com/p?q=1").render() == #"<a href="https://example.com/p?q=1">x</a>"#)
        #expect(a { "x" }.href("/relative/path").render() == #"<a href="/relative/path">x</a>"#)
        #expect(a { "x" }.href("mailto:a@b.co").render() == #"<a href="mailto:a@b.co">x</a>"#)
        #expect(a { "x" }.href("#frag").render() == ##"<a href="#frag">x</a>"##)
    }

    // RFC-0019 §6.3-J: a reactive-hypermedia fragment is built from server data and morphed into the page
    // by the client runtime. The bytes it morphs MUST be escape-by-default — a hostile value cannot smuggle
    // live markup through the morph-apply path (no `RawHTML` on server data). This exercises the fragment
    // byte path (`renderBytes`, what `ADHTMLServe.adhtmlFragment` emits) with the same adversarial vectors.
    @Test(arguments: vectors)
    func `fragment bytes morphed by the runtime are inert`(_ vector: String) {
        let fragment = ul {
            li { vector }.attribute("data-label", vector)
            li { "ok" }
        }
        let out = String(decoding: fragment.renderBytes(), as: UTF8.self)
        #expect(!out.contains("<script"))
        #expect(!out.contains("<img"))
        #expect(!out.contains("<svg"))
        #expect(out.contains("&lt;"))
    }

    // The out-of-band marker is server-controlled, but an attacker-influenced id must still be escaped in
    // the attribute it lands in (the runtime resolves it via getElementById, never by parsing it as markup).
    @Test
    func `out-of-band id is attribute-escaped`() {
        let out = div {}.attribute("x", #""><script>alert(1)</script>"#).render()
        #expect(!out.contains("<script"))
        #expect(out.contains("&quot;") && out.contains("&lt;"))
    }

    // The `.css`/`.scriptJSON` value contexts are SAFE over-escape stubs (route through the attribute
    // encoder until dedicated value encoders land, ADR-0003). Pin that contract: they must stay
    // byte-identical to `.attribute` (so a future change can't silently weaken it) and never under-escape
    // (no raw `<` or `"`), even on CSS/JS-specific breakers.
    @Test(arguments: vectors + ["</style>", "</script>", "expression(", "*/", "`", "\u{2028}"])
    func `css and scriptJSON contexts never under-escape (over-escape stub pinned)`(_ vector: String) {
        func emit(_ context: EscapeContext) -> String {
            var sink = ArraySink()
            Escaper.write(vector, context: context, into: &sink)
            return String(decoding: sink.bytes, as: UTF8.self)
        }
        let attribute = emit(.attribute)
        #expect(emit(.css) == attribute)
        #expect(emit(.scriptJSON) == attribute)
        #expect(!emit(.css).contains("<"))
        #expect(!emit(.css).contains("\""))
    }
}
