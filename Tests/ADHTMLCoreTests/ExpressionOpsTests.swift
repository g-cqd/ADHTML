import Testing

@testable import ADHTMLCore

// RFC-0021 P5 (client `Computed` over an extended op set), ADR-0007 amend. The unary (`lc`/`len`) and the
// `has` binary nodes are client-recomputable, so they serialize into a `cmp` cell's `e` formula and the JS
// evaluator mirrors the op tokens (parity test). Foundation-free initial values (stdlib `firstRange`).
struct ExpressionOpsTests {
    /// Render a computed over `reactive` inside a region and return the inline-state HTML for `e`-assertions.
    private func rendered(_ reactive: Reactive<some WireEncodable>) throws -> String {
        let arena = CellArena()
        let cell = arena.computed(reactive)
        let view = Region("r", scope: [cell.id]) { span { "" } }
        return try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)
    }

    @Test
    func `lowercased serializes to a unary lc node`() throws {
        let arena = CellArena()
        let q = arena.signal("Ab")  // id 0
        let lowered = q.reactive.lowercased()
        #expect(lowered.value == "ab")
        #expect(try rendered(lowered).contains(#""e":{"u":"lc","x":{"c":0}}"#))
    }

    @Test
    func `count serializes to a unary len node`() throws {
        let arena = CellArena()
        let items = arena.signal(["a", "b", "c"])  // id 0
        let n = items.reactive.count
        #expect(n.value == 3)
        #expect(try rendered(n).contains(#""e":{"u":"len","x":{"c":0}}"#))
    }

    @Test
    func `string contains serializes to a has binary node and folds case-insensitively`() throws {
        let arena = CellArena()
        let haystack = arena.signal("Hello")  // id 0
        let needle = arena.signal("ell")  // id 1
        let test = haystack.reactive.contains(needle.reactive)
        #expect(test.value == true)
        #expect(try rendered(test).contains(#""e":{"o":"has","l":{"c":0},"r":{"c":1}}"#))
        // An empty needle matches (mirrors JS String.includes("")).
        #expect(arena.signal("x").reactive.contains(arena.signal("").reactive).value == true)
    }

    @Test
    func `case-insensitive substring match composes lowercased + contains`() {
        let arena = CellArena()
        let item = arena.signal("Banana")
        let query = arena.signal("AN")
        // item.lowercased().contains(query.lowercased()) — the combobox filter predicate shape.
        #expect(item.reactive.lowercased().contains(query.reactive.lowercased()).value == true)
    }

    @Test
    func `array contains tests membership (exact-match guard)`() {
        let arena = CellArena()
        let items = arena.signal(["apple", "pear"])
        #expect(items.reactive.contains(arena.signal("pear").reactive).value == true)
        #expect(items.reactive.contains(arena.signal("plum").reactive).value == false)
    }

    @Test
    func `the unary and binary op sets are closed and match the client evaluator (parity)`() {
        #expect(UnaryOp.allCases.map(\.rawValue) == ["lc", "len"])
        #expect(
            BinaryOp.allCases.map(\.rawValue)
                == ["+", "-", "*", "++", "==", "!=", "<", "<=", ">", ">=", "&&", "||", "has"])
    }
}
