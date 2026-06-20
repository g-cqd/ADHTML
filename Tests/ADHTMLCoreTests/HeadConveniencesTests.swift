import Testing

@testable import ADHTMLCore

// RFC-0020 Tier-1 §1.1 / RFC-0005 §3.6: typed `<head>` conveniences so a document head reads cleanly and
// composes inside a `@HTMLBuilder` head slot. Byte-exact (mutation-resistant) + escape-by-default.
struct HeadConveniencesTests {
    @Test
    func `meta charset defaults to utf-8 and is overridable`() {
        #expect(meta().charset().render() == #"<meta charset="utf-8">"#)
        #expect(meta().charset("iso-8859-1").render() == #"<meta charset="iso-8859-1">"#)
    }

    @Test
    func `Viewport emits the responsive default and accepts an override`() {
        #expect(
            Viewport().render() == #"<meta name="viewport" content="width=device-width, initial-scale=1">"#)
        #expect(Viewport("width=device-width").render() == #"<meta name="viewport" content="width=device-width">"#)
    }

    @Test
    func `Stylesheet and Favicon emit their link rels`() {
        #expect(Stylesheet("/app.css").render() == #"<link rel="stylesheet" href="/app.css">"#)
        #expect(Favicon("/favicon.ico").render() == #"<link rel="icon" href="/favicon.ico">"#)
    }

    @Test
    func `head conveniences are escape-by-default`() {
        // href routes through the URL context — a dangerous scheme is neutralized to the inert placeholder.
        #expect(Stylesheet("javascript:alert(1)").render() == ##"<link rel="stylesheet" href="#">"##)
        // a hostile charset value cannot break out of the attribute.
        let evil = meta().charset(#""><script>alert(1)</script>"#).render()
        #expect(!evil.contains("<script"))
        #expect(evil.contains("&quot;") && evil.contains("&lt;"))
    }
}
