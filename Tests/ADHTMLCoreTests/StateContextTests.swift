import Testing

@testable import ADHTMLCore

// Validates the ambient-context reactive model that `@State` / `@Component` will generate (Phase A0/A1,
// before the macros land). `Counter` is written BY HAND in exactly the shape the macros target: a plain
// stored `count` (the default) plus a `countSignal` accessor that resolves through
// `ADHTMLRenderContext`. These tests pin the three guarantees the model must give: the default renders,
// repeated `@State` reads dedup to one cell, and sibling instances get distinct cells.
struct StateContextTests {
    /// The hand-written equivalent of `@Component struct Counter { @State var count = 0; … }`.
    struct Counter: Component {
        var count: Int = 0
        var countSignal: Signal<Int> { ADHTMLRenderContext.state(key: "count", default: count) }

        var body: some HTML {
            Island("counter", scope: [countSignal.id]) {
                button { "+" }.on("click", Behavior.increment(countSignal))
                span { String(count) }.bind(.text, to: countSignal.id)
            }
        }
    }

    @Test
    func `renders its default and registers exactly one cell despite three reads`() throws {
        let arena = CellArena()
        let html = String(decoding: try Counter().renderHydratable(arena: arena), as: UTF8.self)

        // The stored default reaches the markup; the binding + behavior both point at cell #0.
        #expect(html.contains(#"data-c:click="a#0#1""#))
        #expect(html.contains(#"<span data-e:text="0">0</span>"#))

        // `countSignal` is read three times (island scope, the behavior, the binding) yet dedups to one.
        #expect(arena.cells.count == 1)
        #expect(arena.cells[0].kind == .signal)
        #expect(arena.cells[0].value == .int(0))
    }

    @Test
    func `a non-default initial value flows into the cell and the markup`() throws {
        let arena = CellArena()
        let html = String(decoding: try Counter(count: 7).renderHydratable(arena: arena), as: UTF8.self)
        #expect(html.contains(#"<span data-e:text="0">7</span>"#))
        #expect(arena.cells[0].value == .int(7))
    }

    @Test
    func `sibling component instances get distinct cells (per-instance scope)`() throws {
        let arena = CellArena()
        _ = try div {
            Counter(count: 1)
            Counter(count: 2)
        }
        .renderHydratable(arena: arena)

        #expect(arena.cells.count == 2)
        #expect(arena.cells[0].value == .int(1))
        #expect(arena.cells[1].value == .int(2))
    }

    @Test
    func `a static render needs no arena and still emits the default text`() {
        // No ambient context: `countSignal` falls back to a throwaway arena; `count` is the default.
        #expect(Counter(count: 3).render().contains(">3</span>"))
    }
}
