import Testing

@testable import ADHTMLCore

// Exercises the generated element/attribute surface (ADHTMLCodegen output): elements beyond the former
// hand-curated subset, the new trait-gated attributes (target/content/action/method), void elements, and
// the one Swift-keyword element name (`var`). Compile-time legality is covered by the fact that these
// modifiers only compile on their conforming tags — a `.href` on `<div>` would not build.
struct GeneratedElementsTests {
    @Test
    func `table content composes`() {
        let markup =
            table {
                caption { "Scores" }
                thead { tr { th { "Name" } } }
                tbody { tr { td { "Ada" } } }
            }
            .render()
        #expect(
            markup == "<table><caption>Scores</caption>"
                + "<thead><tr><th>Name</th></tr></thead>"
                + "<tbody><tr><td>Ada</td></tr></tbody></table>")
    }

    @Test
    func `a form carries action/method/target/name`() {
        let markup =
            form {
                input().type("search").name("q")
                button { "Go" }.type("submit")
            }
            .action("/search").method("get").target("_self").name("f")
            .render()
        #expect(markup.hasPrefix(#"<form action="/search" method="get" target="_self" name="f">"#))
        #expect(markup.contains(#"<input type="search" name="q">"#))
        #expect(markup.contains(#"<button type="submit">Go</button>"#))
    }

    @Test
    func `link/meta/base metadata carry their traits`() {
        #expect(
            meta().name("viewport").content("width=device-width").render()
                == #"<meta name="viewport" content="width=device-width">"#)
        #expect(
            link().rel("stylesheet").href("/app.css").type("text/css").render()
                == #"<link rel="stylesheet" href="/app.css" type="text/css">"#)
        #expect(base().href("/").target("_blank").render() == #"<base href="/" target="_blank">"#)
    }

    @Test
    func `an anchor carries target + rel; href stays scheme-allowlisted`() {
        let safe = a { "x" }.href("https://example.com").target("_blank").rel("noopener").render()
        #expect(safe == #"<a href="https://example.com" target="_blank" rel="noopener">x</a>"#)
        // A dangerous scheme is neutralized to an inert `#` by the URL escaping context (ADR-0003).
        let dangerous = a { "x" }.href("javascript:alert(1)").render()
        #expect(dangerous == ##"<a href="#">x</a>"##)
        #expect(!dangerous.contains("javascript:"))
    }

    @Test("the `var` keyword element name is backticked but renders <var>")
    func keywordElement() {
        #expect(`var` { "x" }.render() == "<var>x</var>")
    }

    @Test
    func `new void elements emit no closing tag`() {
        #expect(col().render() == "<col>")
        #expect(wbr().render() == "<wbr>")
        #expect(source().src("/a.webm").type("video/webm").render() == #"<source src="/a.webm" type="video/webm">"#)
        #expect(track().src("/subs.vtt").render() == #"<track src="/subs.vtt">"#)
        #expect(area().href("/").alt("hot").render() == #"<area href="/" alt="hot">"#)
    }

    @Test
    func `interactive + edit + figure elements compose`() {
        #expect(
            details { summary { "More" } }.name("acc").render()
                == #"<details name="acc"><summary>More</summary></details>"#)
        #expect(figure { figcaption { "Fig 1" } }.render() == "<figure><figcaption>Fig 1</figcaption></figure>")
        #expect(del { "old" }.render() == "<del>old</del>")
        #expect(dialog { "hi" }.render() == "<dialog>hi</dialog>")
    }
}
