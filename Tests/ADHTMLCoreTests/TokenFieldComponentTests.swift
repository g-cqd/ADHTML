import ADHTMLCore
import Testing

// The library `TokenField` is the "generic component, machinery hidden" model: an app writes
// `TokenField(name:items:selected:)`, not the cell/island/behavior assembly. It must hydrate with NO
// hand-written JavaScript — composed entirely from the closed declarative primitives.
struct TokenFieldComponentTests {
    @Test func `the generic TokenField hydrates from primitives with no hand-written script`() throws {
        let arena = CellArena()
        let bytes = try TokenField(
            name: "tags", items: ["Swift", "Rust", "Go"], selected: ["Swift"], action: "/tags"
        )
        .renderHydratable(arena: arena)
        let html = String(decoding: bytes, as: UTF8.self)

        #expect(html.contains("data-a"))  // it self-islands
        #expect(html.contains("adh-state"))  // ...and serializes its state
        #expect(arena.cells.count >= 3)  // query + tokens + items (+ filtered computed)
        #expect(html.contains(#"class="tokens""#))  // committed chips
        #expect(html.contains(#"class="suggestions""#))  // suggestion list
        #expect(html.contains("Swift"))  // the seeded chip
        #expect(!html.contains("ADH.mount"))  // NO hand-written component script anywhere
        #expect(!html.contains("<script>"))  // no inline JS at all
    }
}
