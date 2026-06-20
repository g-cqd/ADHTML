import ADTestKit
import Testing

@testable import ADHTMLCore

// Load / concurrency tests (ADTestKit `expectAllConcurrent`, thundering-herd): the render path is
// stateless value-type work, so many concurrent renders must all succeed and be deterministic. This
// guards the invariant — if anyone introduces shared mutable state into the render path, the herd run
// flakes (and TSan would flag it). The reactive path uses a per-render `CellArena` (a `Mutex`-backed
// value), so independent renders never contend.
@Suite(.tags(.concurrency))
struct RenderLoadTests {
    private static func page() -> some HTML {
        div {
            h1 { "Load" }
            _HTMLArray((0 ..< 20).map { index in p { "row \(index)" }.class("r") })
        }
        .class("page")
    }

    @Test
    func `64 concurrent static renders all succeed with byte-identical output (no shared-state race)`() async {
        let expected = Self.page().render()
        let outcome = await expectAllConcurrent(count: 64) { _ in Self.page().render() }
        #expect(outcome.complete)
        #expect(outcome.successCount == 64)
        #expect(outcome.successes.allSatisfy { $0 == expected })
    }

    @Test
    func `64 concurrent hydratable renders with independent arenas all succeed`() async {
        let outcome = await expectAllConcurrent(count: 64) { worker in
            let arena = CellArena()
            let count = arena.signal(worker)
            return try Island("c", scope: [count.id]) { span { "x" }.bind(.text, to: count.id) }
                .renderHydratable(arena: arena)
        }
        #expect(outcome.complete)
        #expect(outcome.successCount == 64)
    }
}
