import ADHTML
import Testing

// Reactive cells created inside a NON-island helper component nested in an island must be owned (and
// therefore serialized) by that island — not dropped. This is what lets a declarative widget (e.g. a
// token-field with `@State` + `ForEach(filteredBy:)` + `.show`) be authored as a plain nested `Component`
// without a hand-written hydration script: before the ownership-bubble fix, the helper's cells leaked out
// of every island scope and the widget silently never hydrated.

@Component
struct Host {  // an island (has @State)
    @State var x = 0
    var body: some HTML {
        div {
            span { String(x) }.bind(.text, to: $x)
            NestedField()  // a plain Component (NOT @Component) that itself uses @State
        }
    }
}

struct NestedField: Component {  // plain conformance — not its own island
    @State var query = ""
    var body: some HTML {
        input().attribute("name", "q").model($query)
    }
}

@Component
struct TwoFields {  // two sibling nested helpers must get DISTINCT cells (per-instance dedup)
    @State var on = false
    var body: some HTML {
        div {
            span { String(on) }.bind(.text, to: $on)  // the island's own cell (0)
            NestedField()  // query (1)
            NestedField()  // query (2)
        }
    }
}

struct NestedIslandScopeTests {
    private func render(_ html: some HTML, _ arena: CellArena) throws -> String {
        String(decoding: try html.renderHydratable(arena: arena), as: UTF8.self)
    }

    @Test
    func `a nested non-island @State bubbles into the enclosing island's serialized scope`() throws {
        let arena = CellArena()
        let html = try render(Host(), arena)
        // Host's `x` (cell 0) and NestedField's `query` (cell 1) are both registered...
        #expect(arena.cells.count == 2)
        // ...and BOTH are in the island's scope — `query` would be DROPPED before the ownership bubble.
        #expect(html.contains(#""scope":[0,1]"#))
        // The nested input's two-way model binds to `query`'s cell, which is present in the wire.
        #expect(html.contains(#"data-i="1""#))
        #expect(html.contains(#"<span data-e:text="0">0</span>"#))
    }

    @Test
    func `sibling nested helpers get distinct cells, all owned by the one island`() throws {
        let arena = CellArena()
        let html = try render(TwoFields(), arena)
        // on (0) + two distinct query cells (1, 2) — per-instance dedup keeps the siblings separate...
        #expect(arena.cells.count == 3)
        // ...and all three are owned by the single enclosing island.
        #expect(html.contains(#""scope":[0,1,2]"#))
        #expect(html.contains(#"data-i="1""#))
        #expect(html.contains(#"data-i="2""#))
    }
}
