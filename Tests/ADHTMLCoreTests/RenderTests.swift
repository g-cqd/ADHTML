import Testing

@testable import ADHTMLCore

struct RenderTests {
    @Test
    func `element with attribute and escaped text`() {
        #expect(div { "a&b" }.class("x").render() == #"<div class="x">a&amp;b</div>"#)
    }

    @Test
    func `nested elements preserve order; each escapes in its own context`() {
        let out = div {
            "Hello, "
            span { "world" }.class("name")
        }
        .class("greeting").render()
        #expect(out == #"<div class="greeting">Hello, <span class="name">world</span></div>"#)
    }

    @Test
    func `void elements emit no closing tag`() {
        #expect(br().render() == "<br>")
    }

    @Test
    func `text escapes & < > but leaves quotes; attributes also escape quotes`() {
        #expect(span { "<a> & x" }.render() == "<span>&lt;a&gt; &amp; x</span>")
        #expect(div {}.attribute("data-x", #"<"'>"#).render() == #"<div data-x="&lt;&quot;&#39;&gt;"></div>"#)
    }

    @Test
    func `class merges (space), id overwrites, insertion order preserved`() {
        #expect(div {}.class("a").class("b").id("x").render() == #"<div class="a b" id="x"></div>"#)
    }

    @Test
    func `RawHTML is emitted verbatim — the single escape hatch`() {
        #expect(div { RawHTML(unsafelyEscaped: "<b>ok</b>") }.render() == "<div><b>ok</b></div>")
    }

    @Test
    func `statically-nested content renders without a depth ceiling`() {
        #expect(div { div { div { "deep" } } }.render() == "<div><div><div>deep</div></div></div>")
    }

    @Test
    func `maxDepth is a failure-safe: adversarial nesting throws, never overflows the stack`() {
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
