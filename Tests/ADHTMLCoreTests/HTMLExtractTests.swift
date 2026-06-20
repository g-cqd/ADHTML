// Gate for structured page extraction (`HTMLDocument.extract`) + the element-query helpers: title
// resolution (og → <title> → h1), meta description, content-container location (selector / fallbacks),
// h2/h3 section splitting, and Markdown vs plain-text section rendering.

import Testing

@testable import ADHTMLCore

struct HTMLExtractTests {
    private let page = """
        <html><head><title>Page Title</title><meta name="description" content="A short desc">
        <meta property="og:title" content="OG Title"></head>
        <body><nav>menu</nav><main><h1>Heading One</h1><p>Intro paragraph.</p>
        <h2>Section A</h2><p>Content A.</p><h2>Section B</h2><p>Content B.</p></main>
        <footer>foot</footer></body></html>
        """

    @Test func resolvesTitleDescriptionAndSections() {
        let extracted = HTMLDocument.extract(page)
        #expect(extracted.title == "OG Title")  // og:title wins over <title>
        #expect(extracted.description == "A short desc")
        #expect(extracted.sections.count == 3)
        #expect(extracted.sections[0].heading == nil)
        #expect(extracted.sections[0].content == "Heading One\n\nIntro paragraph.")
        #expect(extracted.sections[1] == HTMLSection(heading: "Section A", content: "Content A."))
        #expect(extracted.sections[2] == HTMLSection(heading: "Section B", content: "Content B."))
    }

    @Test func singleSectionWhenNoHeadings() {
        let flat = HTMLDocument.extract(
            "<html><head><title>T</title></head><body><article><p>only para</p></article></body></html>")
        #expect(flat.title == "T")
        #expect(flat.description == nil)
        #expect(flat.sections.count == 1)
        #expect(flat.sections[0].content == "only para")
    }

    @Test func titleFallsBackToFirstH1() {
        #expect(HTMLDocument.extract("<body><main><h1>The Heading</h1><p>x</p></main></body>").title == "The Heading")
    }

    @Test func preserveStructureRendersMarkdown() {
        let md = HTMLDocument.extract(
            "<main><h2>S</h2><p>see <a href=\"/x\">link</a></p><ul><li>a</li></ul></main>",
            preserveStructure: true)
        #expect(md.sections[0].content == "see [link](/x)\n\n- a")
    }

    @Test func containerSelectorByClass() {
        let sel = HTMLDocument.extract(
            "<body><div>noise</div><div class=\"content\"><p>real</p></div></body>",
            containerSelector: ".content")
        #expect(sel.sections[0].content == "real")
    }

    @Test func elementQueryHelpers() {
        let node = HTMLNode.parse("<div id=\"main\" class=\"a b\"><span>x</span></div>").first!
        #expect(node.elementID == "main")
        #expect(node.classList == ["a", "b"])
        #expect(node.firstElement(matching: "span")?.textContent == "x")
        #expect([node].firstElement(matching: "#main") != nil)
        #expect([node].firstElement(matching: ".b") != nil)
    }

    @Test func linkResolverThreadsIntoMarkdownSections() {
        let extracted = HTMLDocument.extract(
            "<main><h2>S</h2><p>see <a href=\"/x\">link</a> and <a href=\"http://ext\">ext</a></p></main>",
            preserveStructure: true,
            linkResolver: { href in
                if href == "/x" { return "/docs/x" }  // rewrite internal
                if href.hasPrefix("http://ext") { return nil }  // drop external, keep text
                return href
            })
        #expect(extracted.sections[0].content == "see [link](/docs/x) and ext")
    }

    @Test func splitsByH3WhenNoH2() {
        let extracted = HTMLDocument.extract("<main><h3>A</h3><p>x</p><h3>B</h3><p>y</p></main>")
        #expect(extracted.sections.count == 2)
        #expect(extracted.sections[0] == HTMLSection(heading: "A", content: "x"))
        #expect(extracted.sections[1] == HTMLSection(heading: "B", content: "y"))
    }
}
