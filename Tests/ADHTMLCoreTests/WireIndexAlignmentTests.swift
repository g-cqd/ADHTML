import ADHTMLCore
import Testing

// Regression: the wire-cell array index a binding/behavior emits into the DOM (the RAW creation index) must
// stay aligned with the cell's position in the serialized array. Before the fix, the serializer COMPACTED
// reachable cells to dense indices but the DOM attributes (emitted during lowering, before reachability is
// known) kept the raw index — so a dropped orphan cell ahead of a bound cell silently desynced them: the
// client read `cells[1]` against a length-1 array → undefined → the binding never wired (no crash, no warn).
struct WireIndexAlignmentTests {
    private func render(_ html: some HTML, _ arena: CellArena) throws -> String {
        String(decoding: try html.renderHydratable(arena: arena), as: UTF8.self)
    }

    @Test
    func `a bound cell keeps its raw index when a dropped orphan precedes it`() throws {
        let arena = CellArena()
        _ = arena.signal("ORPHAN")  // index 0 — in no island scope → unreachable (dropped)
        let count = arena.signal(0)  // index 1 — bound + behavior-driven in the DOM
        let view = Island("c", scope: [count.id]) {
            span { "0" }.bind(.text, to: count.id)
            button { "+" }.on("click", Behavior.increment(count))
        }
        let html = try render(view, arena)

        // The DOM refs raw index 1; the wire MUST have a real cell at index 1 (not compacted to 0).
        #expect(html.contains(#"data-e:text="1""#))
        #expect(html.contains(##"data-c:click="a#1#1""##))
        // index 0 is a null placeholder for the dropped orphan; index 1 is `count`.
        #expect(html.contains(#""cells":[{"$":"sig","v":null},{"$":"sig","v":0}]"#))
        #expect(html.contains(#""scope":[1]"#))  // the island scope keeps the raw index too
        // The orphan's VALUE is still dropped — the data-leak guard is intact.
        #expect(!html.contains("ORPHAN"))
    }

    @Test
    func `no orphan means no placeholder — the common path is unchanged + dense`() throws {
        let arena = CellArena()
        let count = arena.signal(5)  // index 0 — the only cell, reachable
        let view = Island("c", scope: [count.id]) {
            span { "5" }.bind(.text, to: count.id)
        }
        let html = try render(view, arena)
        #expect(html.contains(#""cells":[{"$":"sig","v":5}]"#))  // no null placeholder
        #expect(html.contains(#"data-e:text="0""#))
    }
}
