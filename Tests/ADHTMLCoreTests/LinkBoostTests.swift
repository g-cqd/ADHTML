import Testing

@testable import ADHTMLCore

// RFC-0021 P7 — `Link` boost (SPA-feel navigation). A `Link` is a real `<a href>` (the zero-JS baseline);
// `.boost(into:)` adds the `data-adh-link` (`data-z`) wire token naming the `Region` the runtime morphs the
// response into. These assertions pin the rendered wire; the click→fetch→morph→pushState behavior is
// browser-validated (dom.test.js). The `<a href>` always navigates without the runtime — the fallback.
struct LinkBoostTests {
    @Test
    func `a plain Link is just an anchor — the zero-JS navigation baseline`() {
        #expect(Link("Parts", to: "/parts").render() == #"<a href="/parts">Parts</a>"#)
    }

    @Test
    func `boost stamps data-z naming the target region (the only added attribute)`() {
        #expect(
            Link("Parts", to: "/parts").boost(into: "content").render()
                == #"<a href="/parts" data-z="content">Parts</a>"#)
    }

    @Test
    func `the boosted region key is attribute-escaped`() {
        #expect(
            Link("X", to: "/x").boost(into: "a&b").render()
                == #"<a href="/x" data-z="a&amp;b">X</a>"#)
    }

    @Test
    func `boost composes onto any href-bearing element, after the href`() {
        // `.boost` is offered where `Tag: HasHref` (compile-time), and emits after the existing attributes.
        #expect(
            a { Text("Home") }.href("/").class("nav").boost(into: "main").render()
                == #"<a href="/" class="nav" data-z="main">Home</a>"#)
    }

    @Test
    func `the link text is escaped like any Text node`() {
        #expect(Link("A & B", to: "/").render() == #"<a href="/">A &amp; B</a>"#)
    }
}
