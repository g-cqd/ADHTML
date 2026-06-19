import Testing

@testable import ADHTMLCore

@Suite("Wire serialization")
struct WireTests {
    @Test("a counter renders island markup plus a scoped state script")
    func counterEndToEnd() throws {
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

    @Test("non-island state never reaches the wire (the data-leak guard)")
    func dataLeakGuard() throws {
        let arena = CellArena()
        _ = arena.signal("TOP_SECRET")  // not in any island scope
        let shown = arena.signal(7)
        let view = Island("i", scope: [shown.id]) { span { "" } }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        #expect(!html.contains("TOP_SECRET"))
        #expect(html.contains(#""v":7"#))
    }

    @Test("a computed pulls its dependencies into scope and re-indexes refs")
    func computedReachability() throws {
        let arena = CellArena()
        let a = arena.signal(1)
        let doubled = arena.computed { a.value * 2 }
        let view = Island("i", scope: [doubled.id]) { span { "" } }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        #expect(html.contains(#""$":"cmp""#))
        #expect(html.contains(#""d":[0]"#))  // doubled depends on `a`, re-indexed to 0
        #expect(html.contains(#""v":2"#))
    }

    @Test("a </script> in state is escaped and cannot break out")
    func scriptBreakout() throws {
        let arena = CellArena()
        let evil = arena.signal("</script><script>alert(1)</script>")
        let view = Island("i", scope: [evil.id]) { span { "" } }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        #expect(!html.contains("</script><script>"))  // the injected double-tag is neutralized
        #expect(html.contains("\\u003c"))  // escaping happened: the literal < became <
        #expect(html.hasSuffix("</script>"))  // only the legitimate closer remains
    }

    @Test("an event binding emits data-adh-on with behavior#cell#param")
    func eventBinding() throws {
        let arena = CellArena()
        let count = arena.signal(0)
        let view = Island("c", scope: [count.id]) {
            button { "+" }.on("click", Behavior.increment(count))
        }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)

        #expect(html.contains(##"data-adh-on:click="increment#0#1""##))
    }
}
