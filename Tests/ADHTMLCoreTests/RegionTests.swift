import Testing

@testable import ADHTMLCore

// RFC-0020 §1.6 / ADR-0016: a `Region` is a stably-keyed `Island` whose author-given key is stamped as
// BOTH `b` (SSE-morph + wiring selector) and a plain `id` (the `getElementById` target the
// RFC-0019 action interpreter resolves a morph target by). The key survives an independent page-vs-fragment
// re-render, so the same element morphs in both. The plain `id` is additive: an `Island` / implicit island
// stays byte-identical (no `id`).
struct RegionTests {
    @Test
    func `a region stamps its key as both a plain id and b`() {
        #expect(
            Region(.content) { span { "x" } }.render()
                == #"<div a id="content" b="content" c="load">"#
                + #"<span>x</span></div>"#
        )
    }

    @Test
    func `a region carries its loading strategy and SSE connect like an island`() {
        #expect(
            Region("rows", on: .visible, connect: "/parts/stream") { span { "rows" } }.render()
                == #"<div a id="rows" b="rows" c="visible" "#
                + #"d="/parts/stream"><span>rows</span></div>"#
        )
    }

    @Test
    func `a region's key is attribute-escaped in both id and b`() {
        #expect(
            Region("a&b") {}.render()
                == #"<div a id="a&amp;b" b="a&amp;b" c="load"></div>"#
        )
    }

    @Test
    func `a plain Island stays byte-identical — no plain id (the change is additive)`() {
        #expect(
            Island("isle", on: .visible) { span { "x" } }.render()
                == #"<div a b="isle" c="visible"><span>x</span></div>"#
        )
    }

    @Test
    func `a region registers in the wire as an island and serializes its scoped cells`() throws {
        let arena = CellArena()
        let count = arena.signal(0)
        let view = Region(.content, scope: [count.id]) {
            span { "0" }.bind(.text, to: count)
        }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        // Markup: the region root carries both ids; the binding is inside it.
        #expect(html.hasPrefix(#"<div a id="content" b="content" c="load">"#))
        // Wire: the region is an island keyed by its stable id, scope [0]; the cell is reachable.
        #expect(html.contains(#""islands":[{"id":"content","on":"load","scope":[0]}]"#))
        #expect(html.contains(#"{"$":"sig","v":0}"#))
    }

    @Test
    func `the region id bridges to the island id space for action targeting`() {
        #expect(RegionID.content.islandID == IslandID("content"))
        #expect(RegionID("x").islandID.raw == "x")
    }
}

extension RegionID {
    /// A region key for the tests (apps name their regions this way: `Region(.content)`).
    fileprivate static let content = RegionID("content")
}
