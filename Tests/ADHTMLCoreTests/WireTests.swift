import Testing

@testable import ADHTMLCore

struct WireTests {
    @Test
    func `a counter renders island markup plus a scoped state script`() throws {
        let arena = CellArena()
        let count = arena.signal(0)
        let view = Island("counter", on: .visible, scope: [count.id]) {
            span { "0" }.bind(.text, to: count.id)
        }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        #expect(
            html.hasPrefix(
                #"<div data-adh-island data-adh-id="counter" data-adh-on="visible"><span data-adh-bind:text="0">0</span></div>"#
            ))
        #expect(html.contains(#"<script type="application/adh-state+json" id="adh-state">"#))
        #expect(html.contains(#""v":1"#))
        #expect(html.contains(#""$":"sig""#))
        #expect(html.contains(#""id":"counter""#))
        #expect(html.contains(#""on":"visible""#))
        #expect(html.contains(#""scope":[0]"#))
        #expect(html.hasSuffix("</script>"))
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
    func `array nesting past the depth cap throws (failure-safe, never a stack crash)`() {
        var deep: WireValue = .int(0)
        for _ in 0 ... (WireSerializer.maxValueDepth + 4) { deep = .array([deep]) }
        let cell = CellArena.Cell(id: CellID(0), kind: .signal, value: deep)
        let island = WireIsland(id: "i", on: .load, scope: [CellID(0)])
        #expect(throws: WireError.self) {
            _ = try WireSerializer.payload(cells: [cell], islands: [island])
        }
    }

    @Test
    func `an event binding emits data-adh-on with behavior#cell#param`() throws {
        let arena = CellArena()
        let count = arena.signal(0)
        let view = Island("c", scope: [count.id]) {
            button { "+" }.on("click", Behavior.increment(count))
        }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        #expect(html.contains(##"data-adh-on:click="increment#0#1""##))
    }
}
