import Testing

@testable import ADHTMLCore

struct WireTests {
    /// Render the canonical counter island once (extracted so each test's body stays small enough to
    /// type-check fast — the DSL builder + many `#expect`s in one body otherwise trips the timing gate).
    private func renderedCounter() throws -> String {
        let arena = CellArena()
        let count = arena.signal(0)
        let view = Island("counter", on: .visible, scope: [count.id]) {
            span { "0" }.bind(.text, to: count.id)
        }
        return try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)
    }

    @Test
    func `a counter renders its island markup`() throws {
        let html = try renderedCounter()
        #expect(
            html.hasPrefix(
                #"<div data-a data-b="counter" data-c="visible"><span data-e:text="0">0</span></div>"#
            ))
        #expect(html.hasSuffix("</script>"))
    }

    /// The exact inline-state JSON between the `adh-state` script tags — for byte-exact payload assertions
    /// (a substring `.contains` would survive a key reorder, a wrong value elsewhere, or a missing field).
    private static func inlineStatePayload(_ html: String) throws -> String {
        // `firstRange(of:)` is stdlib (no Foundation — ADHTMLCore is Foundation-free, and the test target
        // enables MemberImportVisibility). The payload escapes `<`, so the only literal `</script>` is the
        // state closer.
        let open = #"<script type="application/adh-state+json" id="adh-state">"#
        let start = try #require(html.firstRange(of: open))
        let rest = html[start.upperBound...]
        let end = try #require(rest.firstRange(of: "</script>"))
        return String(rest[..<end.lowerBound])
    }

    @Test
    func `a counter embeds the EXACT scoped state payload (not just substrings)`() throws {
        let payload = try Self.inlineStatePayload(renderedCounter())
        #expect(
            payload == #"{"v":1,"cells":[{"$":"sig","v":0}],"#
                + #""islands":[{"id":"counter","on":"visible","scope":[0]}]}"#)
    }

    @Test
    func `non-island state never reaches the wire (the data-leak guard)`() throws {
        let arena = CellArena()
        _ = arena.signal("TOP_SECRET")  // not in any island scope
        let shown = arena.signal(7)
        let view = Island("i", scope: [shown.id]) { span { "" } }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        #expect(!html.contains("TOP_SECRET"))
        #expect(html.contains(#""v":7"#))
    }

    @Test
    func `a computed pulls its dependencies into scope and re-indexes refs`() throws {
        let arena = CellArena()
        let a = arena.signal(1)
        let doubled = arena.computed { a.value * 2 }
        let view = Island("i", scope: [doubled.id]) { span { "" } }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        #expect(html.contains(#""$":"cmp""#))
        #expect(html.contains(#""d":[0]"#))  // doubled depends on `a`, re-indexed to 0
        #expect(html.contains(#""v":2"#))
    }

    @Test
    func `a </script> in state is escaped and cannot break out`() throws {
        let arena = CellArena()
        let evil = arena.signal("</script><script>alert(1)</script>")
        let view = Island("i", scope: [evil.id]) { span { "" } }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        #expect(!html.contains("</script><script>"))  // the injected double-tag is neutralized
        #expect(html.contains("\\u003c"))  // escaping happened: the literal < became <
        #expect(html.hasSuffix("</script>"))  // only the legitimate closer remains
    }

    @Test
    func `a nested-array cell value serializes (iterative WireValue -> JSON, no recursion)`() throws {
        let arena = CellArena()
        let matrix = arena.signal([[1, 2], [3]])
        let view = Island("i", scope: [matrix.id]) { span { "" } }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)
        #expect(html.contains(#""v":[[1,2],[3]]"#))
    }

    @Test
    func `array nesting is bounded exactly at the cap (failure-safe boundary, never a stack crash)`() {
        func nested(_ depth: Int) -> WireValue {
            var value: WireValue = .int(0)
            for _ in 0 ..< depth { value = .array([value]) }
            return value
        }
        func serialize(_ value: WireValue) throws {
            let cell = CellArena.Cell(id: CellID(0), kind: .signal, value: value)
            _ = try WireSerializer.payload(cells: [cell], islands: [WireIsland(id: "i", on: .load, scope: [CellID(0)])])
        }
        let cap = WireSerializer.maxValueDepth
        // At the cap: serializes. One deeper: throws (not a stack crash — the walk is iterative).
        #expect(throws: Never.self) { try serialize(nested(cap)) }
        #expect(throws: WireError.self) { try serialize(nested(cap + 1)) }
    }

    @Test
    func `an event binding emits c with behavior#cell#param`() throws {
        let arena = CellArena()
        let count = arena.signal(0)
        let view = Island("c", scope: [count.id]) {
            button { "+" }.on("click", Behavior.increment(count))
        }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        #expect(html.contains(##"data-c:click="a#0#1""##))
    }

    @Test
    func `a reactive computed serializes a client-recomputable expression (e)`() throws {
        let arena = CellArena()
        let count = arena.signal(3)
        let doubled = arena.computed(count.reactive * 2)
        #expect(doubled.value == 6)

        let view = Island("i", scope: [doubled.id]) { span { "" } }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        #expect(html.contains(#""$":"cmp""#))
        #expect(html.contains(#""v":6"#))  // server-evaluated initial value
        // `count` reindexed to 0; the formula is `cell(0) * 2`.
        #expect(html.contains(#""e":{"o":"*","l":{"c":0},"r":{"i":2}}"#))
    }

    @Test
    func `a closure computed carries no expression`() throws {
        let arena = CellArena()
        let base = arena.signal(5)
        let derived = arena.computed { base.value + 1 }
        let view = Island("i", scope: [derived.id]) { span { "" } }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)
        #expect(html.contains(#""$":"cmp""#))
        #expect(!html.contains(#""e":"#))  // opaque closure -> no client formula
    }

    @Test
    func `the binary op set matches the client evaluator (Swift<->JS parity)`() {
        #expect(
            Set(BinaryOp.allCases.map(\.rawValue))
                == ["+", "-", "*", "++", "==", "!=", "<", "<=", ">", ">=", "&&", "||", "has"])
    }

    @Test
    func `comparison and boolean operators build reactive Bool expressions`() {
        let arena = CellArena()
        let count = arena.signal(3)
        let flag = arena.signal(true)
        #expect((count.reactive > 2).value == true)
        #expect((count.reactive == 3).value == true)
        #expect((count.reactive != 4).value == true)
        #expect((flag.reactive && (count.reactive < 5)).value == true)
        #expect((flag.reactive || false).value == true)
        #expect((!flag.reactive).value == false)

        guard case .binary(let op, _, _) = (count.reactive >= 3).expr else {
            Issue.record("expected a binary expr")
            return
        }
        #expect(op == .gte)
        // `!flag` is modelled as `flag == false` (no separate unary node).
        guard case .binary(.eq, _, .bool(let constant)) = (!flag.reactive).expr else {
            Issue.record("expected eq-false")
            return
        }
        #expect(constant == false)
    }
}
