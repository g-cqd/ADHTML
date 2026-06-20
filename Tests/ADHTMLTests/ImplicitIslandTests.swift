import ADHTML
import Testing

// Implicit islands (RFC-0005 §3.0 / ADR-0015 C): an interactive `@Component` auto-wraps as an island
// with an inferred scope; a static one renders inline (no island, no JS); a computed property binds as a
// client-recomputable cell — all with NO `Island`/`scope`/`.id` in the authored code.

@Component
struct StaticCard {
    let title: String
    var body: some HTML { article { h3 { title } } }  // no @State -> stays a plain Component
}

@Component
struct LazyCounter {
    @State var n = 0
    static var hydration: LoadStrategy { .visible }  // override the default .load

    var body: some HTML {
        div {
            button { "+" }.on(.click, Behavior.increment(nSignal))
            span { String(n) }.bind(.text, to: nSignal)
        }
    }
}

@Component
struct Sum {
    @State var a = 2
    @State var b = 3
    var total: Reactive<Int> { aSignal.reactive + bSignal.reactive }  // a plain computed property

    var body: some HTML {
        div {
            button { "+" }.on(.click, Behavior.increment(aSignal))
            output { String(a + b) }.bind(.text, to: total)
        }
    }
}

struct ImplicitIslandTests {
    @Test
    func `a static component renders inline — no island, no JS`() throws {
        let html = String(decoding: try StaticCard(title: "Hi").renderHydratable(arena: CellArena()), as: UTF8.self)
        #expect(!html.contains("<div a"))  // no island root (the bare `a` marker) — renders inline
        #expect(html.contains("<article><h3>Hi</h3></article>"))
    }

    @Test
    func `the hydration override makes the implicit island lazy`() throws {
        let html = String(decoding: try LazyCounter().renderHydratable(arena: CellArena()), as: UTF8.self)
        #expect(html.contains(#"<div data-a data-b="c1" data-c="visible">"#))
    }

    @Test
    func `a computed property binds as a client-recomputable cell`() throws {
        let arena = CellArena()
        let html = String(decoding: try Sum().renderHydratable(arena: arena), as: UTF8.self)

        // a=cell0 (behavior), b=cell1 (in total), total=cell2 (the registered computed); value 2+3 = 5.
        #expect(html.contains(#"<output data-e:text="2">5</output>"#))
        #expect(arena.cells.count == 3)
        guard case .computed(_, let expr) = arena.cells[2].kind else {
            Issue.record("cell 2 should be a computed")
            return
        }
        #expect(expr != nil)  // carries a WireExpr -> the client re-evaluates it (no SSE round-trip)
    }
}
