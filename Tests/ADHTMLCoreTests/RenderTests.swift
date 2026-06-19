import Testing

@testable import ADHTMLCore

@Suite("Rendering")
struct RenderTests {
    @Test("element with attribute and escaped text")
    func basic() {
        #expect(div { "a&b" }.class("x").render() == #"<div class="x">a&amp;b</div>"#)
    }

    @Test("nested elements preserve order; each escapes in its own context")
    func nested() {
        let out = div {
            "Hello, "
            span { "world" }.class("name")
        }
        .class("greeting").render()
        #expect(out == #"<div class="greeting">Hello, <span class="name">world</span></div>"#)
    }

    @Test("void elements emit no closing tag")
    func voidElement() {
        #expect(br().render() == "<br>")
    }

    @Test("text escapes & < > but leaves quotes; attributes also escape quotes")
    func escaping() {
        #expect(span { "<a> & x" }.render() == "<span>&lt;a&gt; &amp; x</span>")
        #expect(div {}.attribute("data-x", #"<"'>"#).render() == #"<div data-x="&lt;&quot;&#39;&gt;"></div>"#)
    }

    @Test("class merges (space), id overwrites, insertion order preserved")
    func attributeMerge() {
        #expect(div {}.class("a").class("b").id("x").render() == #"<div class="a b" id="x"></div>"#)
    }

    @Test("RawHTML is emitted verbatim — the single escape hatch")
    func raw() {
        #expect(div { RawHTML(unsafelyEscaped: "<b>ok</b>") }.render() == "<div><b>ok</b></div>")
    }

    @Test("statically-nested content renders without a depth ceiling")
    func deepStatic() {
        #expect(div { div { div { "deep" } } }.render() == "<div><div><div>deep</div></div></div>")
    }

    @Test("maxDepth is a failure-safe: adversarial nesting throws, never overflows the stack")
    func maxDepthFailSafe() {
        var program = HTMLProgram()
        for _ in 0 ..< 500 {
            program.append(.openTagStart("div"))
            program.append(.openTagEnd)
        }
        for _ in 0 ..< 500 { program.append(.closeTag("div")) }
        #expect(throws: RenderError.self) {
            var sink = ArraySink()
            try Renderer.render(program, into: &sink, maxDepth: 64)
        }
    }
}
