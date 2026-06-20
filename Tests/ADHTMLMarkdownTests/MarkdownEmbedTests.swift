import ADHTMLCore
import Testing

@testable import ADHTMLMarkdown

// `Markdown` with embedded ADHTML components — both authoring surfaces, escape-by-default, and FULL
// hydration fidelity (an embedded island lands in the page program where the hydration scan finds it).
// The target imports ADHTMLCore for the embedded primitives (button/span/div/Island/CellArena/Behavior).
struct MarkdownEmbedTests {
    private func bytes(_ markdown: Markdown, arena: CellArena) throws -> String {
        String(decoding: try markdown.renderHydratable(arena: arena), as: UTF8.self)
    }

    // MARK: - string form, static embedding

    @Test
    func `an inline component splices into the rendered prose (byte-exact)`() {
        let html = Markdown("# Heading\n\nBuy: \(button { "Buy" })").render()
        #expect(html == "<h1>Heading</h1>\n<p>Buy: <button>Buy</button></p>\n")
    }

    @Test
    func `a block component alone in a paragraph unwraps the wrapping <p>`() {
        let html = Markdown("# T\n\n\(div { "X" })").render()
        // `<p><div>…</div></p>` would be invalid HTML; the lone-paragraph slot is unwrapped.
        #expect(html == "<h1>T</h1>\n<div>X</div>\n")
    }

    // MARK: - the sentinel never leaks

    @Test
    func `no Private-Use-Area sentinel ever reaches the output`() {
        let html = Markdown("a \(button { "x" }) b \(span { "y" }) c").render()
        #expect(!html.unicodeScalars.contains { $0.value >= 0xE000 && $0.value <= 0xF8FF })
        #expect(html.contains("<button>x</button>"))
        #expect(html.contains("<span>y</span>"))
    }

    // MARK: - escaping / XSS

    @Test
    func `an untrusted text interpolation cannot inject markup, and an adjacent slot stays intact`() {
        let html = Markdown("\(text: "</p><script>alert(1)</script>") \(button { "ok" })").render()
        #expect(!html.contains("<script>"))  // the injected tag is neutralized
        #expect(html.contains("&lt;script&gt;"))  // shown as literal text
        #expect(html.contains("<button>ok</button>"))  // the real slot survived the splice
    }

    @Test
    func `a javascript link destination is neutralized by the renderer`() {
        let html = Markdown("[click](\(url: "javascript:alert(1)"))").render()
        #expect(!html.contains("javascript:"))
    }

    @Test
    func `author markdown cannot smuggle raw HTML when allowRawHTML is off`() {
        let html = Markdown("<script>evil()</script>\n\nok").render()
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    // MARK: - P2: full island fidelity

    @Test
    func `an embedded @State island lands in the program and reaches the wire`() throws {
        let arena = CellArena()
        let count = arena.signal(0)
        let island = Island("embedded", scope: [count.id]) {
            span { "0" }.bind(.text, to: count.id)
        }
        let html = try bytes(Markdown("# Live\n\nWidget: \(island)"), arena: arena)

        #expect(html.contains("<h1>Live</h1>"))
        #expect(html.contains(#"data-b="embedded""#))  // the island root landed in the page program
        #expect(html.contains(#"<span data-e:text="0">0</span>"#))  // the binding survived the splice
        #expect(html.contains(#""islands":[{"id":"embedded""#))  // and reached the hydration wire
        #expect(html.contains(#""cells":[{"$":"sig","v":0}]"#))  // with its scoped cell
    }

    @Test
    func `an embedded delegated action keeps its data-adh attribute through the splice`() throws {
        let arena = CellArena()
        let count = arena.signal(0)
        let html = try bytes(
            Markdown("Tap: \(button { "+" }.on(.click, Behavior.increment(count)))"), arena: arena)
        #expect(html.contains("data-c:click="))  // attribute-only action → always live
    }

    // MARK: - nesting + builder control flow

    @Test
    func `a nested Markdown renders by recursion`() {
        let html = Markdown("# Outer\n\n\(Markdown("**inner**"))").render()
        #expect(html.contains("<h1>Outer</h1>"))
        #expect(html.contains("<strong>inner</strong>"))
    }

    @Test
    func `the builder form supports if and for over fragments and components`() {
        let items = ["a", "b"]
        func page(hot: Bool) -> String {
            Markdown {
                "# Title"
                if hot { button { "HOT" } }
                for item in items { "- \(item)" }
            }
            .render()
        }
        // ADHTMLMarkdown wraps every list item's content in `<p>` (it renders the item's Paragraph child),
        // so the `for`-built list items are `<li><p>a</p>…`.
        let withBadge = page(hot: true)
        #expect(withBadge.contains("<h1>Title</h1>"))
        #expect(withBadge.contains("<button>HOT</button>"))
        #expect(withBadge.contains("<ul>\n<li><p>a</p>"))
        #expect(withBadge.contains("<li><p>b</p>"))

        let withoutBadge = page(hot: false)
        #expect(!withoutBadge.contains("<button>HOT</button>"))
        #expect(withoutBadge.contains("<li><p>a</p>"))
    }
}
