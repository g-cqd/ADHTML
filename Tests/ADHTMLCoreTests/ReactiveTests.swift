import Testing

@testable import ADHTMLCore

@Suite("Reactivity")
struct ReactiveTests {
    @Test("a signal carries its value and registers a cell")
    func signal() {
        let arena = CellArena()
        let count = arena.signal(0)
        #expect(count.value == 0)
        #expect(arena.cells.count == 1)
        #expect(arena.cells[0].kind == .signal)
        #expect(arena.cells[0].value == .int(0))
    }

    @Test("a computed captures the cells it reads, in order")
    func computedDependencies() {
        let arena = CellArena()
        let a = arena.signal(2)
        let b = arena.signal(3)
        let sum = arena.computed { a.value + b.value }
        #expect(sum.value == 5)

        let cells = arena.cells
        #expect(cells.count == 3)
        guard case .computed(let deps) = cells[2].kind else {
            Issue.record("expected a computed cell")
            return
        }
        #expect(deps == [a.id, b.id])
        #expect(cells[2].value == .int(5))
    }

    @Test("a computed that reads nothing has no dependencies")
    func computedWithoutDependencies() {
        let arena = CellArena()
        let answer = arena.computed { 42 }
        #expect(answer.value == 42)
        guard case .computed(let deps) = arena.cells[0].kind else {
            Issue.record("expected a computed cell")
            return
        }
        #expect(deps.isEmpty)
    }

    @Test("a computed can depend on another computed")
    func chainedComputed() {
        let arena = CellArena()
        let base = arena.signal(10)
        let doubled = arena.computed { base.value * 2 }
        let plusOne = arena.computed { doubled.value + 1 }
        #expect(plusOne.value == 21)
        guard case .computed(let deps) = arena.cells[2].kind else {
            Issue.record("expected a computed cell")
            return
        }
        #expect(deps == [doubled.id])
    }
}
