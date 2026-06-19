import Testing

@testable import ADHTMLCore

/// Adversarial output-encoding tests (ADR-0003). Output must be XSS-safe by construction: a value
/// placed in any context can never introduce live markup or a dangerous URL scheme.
@Suite("XSS safety")
struct XSSTests {
    static let vectors = [
        "<script>alert(1)</script>",
        #""><img src=x onerror=alert(1)>"#,
        "<svg/onload=alert(1)>",
        #"'><script>alert(1)</script>"#,
        "</span><script>alert(1)</script>"
    ]

    @Test("text-context vectors render inert", arguments: vectors)
    func textInert(_ vector: String) {
        let out = span { vector }.render()
        #expect(!out.contains("<script"))
        #expect(!out.contains("<img"))
        #expect(!out.contains("<svg"))
        #expect(out.contains("&lt;"))
    }

    @Test("attribute-context vectors cannot inject markup", arguments: vectors)
    func attributeInert(_ vector: String) {
        let out = div {}.attribute("title", vector).render()
        #expect(!out.contains("<script"))
        #expect(!out.contains("<img"))
        #expect(!out.contains("<svg"))
        #expect(out.contains("&quot;") || !vector.contains("\""))
    }

    @Test("dangerous href schemes are neutralized to an inert placeholder")
    func dangerousSchemes() {
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

    @Test("safe href schemes and relative URLs pass through")
    func safeSchemes() {
        #expect(a { "x" }.href("https://example.com/p?q=1").render() == #"<a href="https://example.com/p?q=1">x</a>"#)
        #expect(a { "x" }.href("/relative/path").render() == #"<a href="/relative/path">x</a>"#)
        #expect(a { "x" }.href("mailto:a@b.co").render() == #"<a href="mailto:a@b.co">x</a>"#)
        #expect(a { "x" }.href("#frag").render() == ##"<a href="#frag">x</a>"##)
    }
}
