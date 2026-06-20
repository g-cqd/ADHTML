import ADTestKit
import Testing

@testable import ADHTMLCore

struct RenderTests {
    /// A `depth`-deep `<div>…</div>` program (open `depth` tags, then close them).
    private static func nestedDivs(depth: Int) -> HTMLProgram {
        var program = HTMLProgram()
        for _ in 0 ..< depth {
            program.append(.openTagStart("div"))
            program.append(.openTagEnd)
        }
        for _ in 0 ..< depth { program.append(.closeTag("div")) }
        return program
    }

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
    func `maxDepth is exact: depth == cap renders, cap+1 throws the pinned error (off-by-one resistant)`() {
        let cap = 8
        // Depth exactly at the cap renders — the throw is `depth > maxDepth`, not `>=`. A mutation flipping
        // that comparison breaks this case.
        #expect(throws: Never.self) {
            var sink = ArraySink()
            try Renderer.render(Self.nestedDivs(depth: cap), into: &sink, maxDepth: cap)
        }
        // One deeper throws — and the payload is pinned to the exact cap (an off-by-one in the counter
        // would report a different value or not throw).
        expectThrows(
            {
                var sink = ArraySink()
                try Renderer.render(Self.nestedDivs(depth: cap + 1), into: &sink, maxDepth: cap)
            },
            where: { (error: RenderError) in error == .maxDepthExceeded(cap) })
    }

    @Test
    func `the renderer is non-recursive: a 2000-deep program renders on a 512 KiB stack, never SIGBUS`() {
        // Survival of the constrained-stack run IS the assertion: a recursive renderer would overflow and
        // SIGBUS at this depth; the iterative emit returns. The bounded path throws (failure-safe), never
        // crashes. Proves the "no recursion over the value tree" invariant structurally.
        runOnConstrainedStack {
            let program = Self.nestedDivs(depth: 2000)
            var sink = ArraySink()
            Renderer.render(program, into: &sink)  // unbounded iterative emit: must not overflow
            var bounded = ArraySink()
            #expect(throws: RenderError.self) {
                try Renderer.render(program, into: &bounded, maxDepth: Renderer.defaultMaxDepth)
            }
        }
    }
}
