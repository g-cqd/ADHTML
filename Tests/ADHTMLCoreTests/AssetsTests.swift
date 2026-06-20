import Testing

@testable import ADHTMLCore

// Track 4 — component-scoped assets (the Foundation-free core surface): the Swift-native CSS scoper, the
// asset surface + dedup, the `data-component`/`data-scope` mount root, and the no-FOUC `<style>` injection.
struct AssetsTests {
    /// Scope CSS with a FIXED scope string so the output is byte-exact (the real hash is per-type).
    private func scoped(_ css: StaticString) -> String {
        let bytes = css.withUTF8Buffer { unsafe Array($0) }
        return String(decoding: CSSScoper.scope(bytes, scope: "z9"), as: UTF8.self)
    }

    // MARK: - the CSS scoper (byte-exact)

    @Test
    func `a top-level selector gains the scope ancestor`() {
        #expect(scoped(".foo { color: red }") == #"[data-1="z9"] .foo { color: red }"#)
    }

    @Test
    func `a comma selector list prefixes each selector`() {
        #expect(scoped(".a, .b { x: y }") == #"[data-1="z9"] .a, [data-1="z9"] .b { x: y }"#)
    }

    @Test
    func `a comma inside brackets does not split the selector`() {
        #expect(scoped(#"a[data-x="1,2"] { c: d }"#) == #"[data-1="z9"] a[data-x="1,2"] { c: d }"#)
    }

    @Test
    func `@media recurses one level and scopes the inner selectors`() {
        #expect(
            scoped("@media (min-width: 600px) { .a { x: y } }")
                == #"@media (min-width: 600px) { [data-1="z9"] .a { x: y } }"#)
    }

    @Test
    func `@keyframes is copied verbatim (its stops are not page selectors)`() {
        let css: StaticString = "@keyframes spin { from { transform: rotate(0) } to { transform: rotate(1turn) } }"
        #expect(scoped(css) == "@keyframes spin { from { transform: rotate(0) } to { transform: rotate(1turn) } }")
    }

    @Test
    func `@font-face and @import are copied verbatim`() {
        #expect(scoped("@import url(\"x.css\");") == "@import url(\"x.css\");")
        #expect(
            scoped("@font-face { font-family: A; src: url(a.woff2) }")
                == "@font-face { font-family: A; src: url(a.woff2) }")
    }

    @Test
    func `a .global class opts out of scoping`() {
        #expect(scoped(".global .a { c: d }") == ".global .a { c: d }")
    }

    @Test
    func `:global(...) unwraps and opts out`() {
        #expect(scoped(":global(.a) .b { c: d }") == ".a .b { c: d }")
    }

    @Test
    func `malformed unbalanced CSS stays bounded (never crashes, never unscoped-unbounded)`() {
        // A missing close brace: the scoper treats the rest as the rule body and stays bounded.
        _ = scoped(".a { color: red")  // does not crash
    }

    // MARK: - base36

    @Test
    func `base36 encodes compactly`() {
        #expect(base36(0) == "0")
        #expect(base36(35) == "z")
        #expect(base36(36) == "10")
    }
}

// A static (non-interactive) component carrying scoped CSS — a `data-component` mount root, no wire cells.
private struct StyledCard: Component {
    let title: String
    static var style: ScopedStyle? { ScopedStyle(".card { color: red } .badge { font-weight: bold }") }
    var body: some HTML { article { h3 { title } }.class("card") }
}

// An interactive component (island) carrying scoped CSS — the island nests INSIDE the mount root.
private struct StyledIsland: Component {
    static var isIsland: Bool { true }
    static var style: ScopedStyle? { ScopedStyle(".w { color: blue }") }
    var body: some HTML { div { "hi" }.class("w") }
}

extension AssetsTests {
    private func render(_ html: some HTML, arena: CellArena = CellArena()) throws -> String {
        String(decoding: try html.renderHydratable(arena: arena), as: UTF8.self)
    }

    /// The `data-scope` value stamped on the first mount root in `html`.
    private func scopeHash(in html: String) throws -> String {
        let marker = #"data-1=""#
        let start = try #require(html.firstRange(of: marker))
        let rest = html[start.upperBound...]
        let end = try #require(rest.firstRange(of: "\""))
        return String(rest[..<end.lowerBound])
    }

    @Test
    func `a styled component stamps a mount root and injects one scoped style (no FOUC)`() throws {
        let html = try render(StyledCard(title: "Hi"))
        let hash = try scopeHash(in: html)

        // The mount root wraps the body, carrying the component name + scope.
        #expect(html.contains(#"<div data-0="StyledCard" data-1="\#(hash)"><article class="card">"#))
        // The scoped `<style>` is injected, with every selector confined under the scope ancestor.
        #expect(html.contains(#"<style>[data-1="\#(hash)"] .card { color: red } [data-1="\#(hash)"] .badge"#))
        // No FOUC: the `<style>` precedes the inline state script.
        let styleAt = try #require(html.firstRange(of: "<style>"))
        let stateAt = try #require(html.firstRange(of: #"id="adh-state""#))
        #expect(styleAt.lowerBound < stateAt.lowerBound)
    }

    @Test
    func `two instances of one styled type inject the style only once (dedup)`() throws {
        let html = try render(
            div {
                StyledCard(title: "A")
                StyledCard(title: "B")
            })
        // Two mount roots…
        let firstRoot = try #require(html.firstRange(of: #"data-0="StyledCard""#))
        #expect(html[firstRoot.upperBound...].contains(#"data-0="StyledCard""#))  // a second one exists
        // …but exactly one `<style>` block.
        #expect(Self.count(of: "<style>", in: html) == 1)
    }

    /// Count non-overlapping occurrences of `needle` (stdlib `firstRange`, no Foundation).
    private static func count(of needle: String, in haystack: String) -> Int {
        var total = 0
        var rest = Substring(haystack)
        while let range = rest.firstRange(of: needle) {
            total += 1
            rest = rest[range.upperBound...]
        }
        return total
    }

    @Test
    func `an interactive styled component nests its island inside the mount root`() throws {
        let html = try render(StyledIsland())
        let hash = try scopeHash(in: html)
        #expect(
            html.contains(#"<div data-0="StyledIsland" data-1="\#(hash)"><div data-a data-b="c1" data-c="load">"#))
        #expect(html.contains(#"<style>[data-1="\#(hash)"] .w { color: blue }</style>"#))
    }

    @Test
    func `a static render emits no mount root and no style (the SSR/no-asset fallback)`() {
        let html = StyledCard(title: "Hi").render()
        #expect(!html.contains("data-0="))  // no mount root
        #expect(!html.contains("<style>"))  // no injected CSS
        #expect(html.contains(#"<article class="card"><h3>Hi</h3></article>"#))  // body is the fallback
    }
}
