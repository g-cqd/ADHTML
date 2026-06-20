import Testing

@testable import ADHTMLCore

// The shared wire-attribute vocabulary (RFC-0021 / ADR-0019). `WireToken` is GENERATED from
// `wire-tokens.json` by the `generate-wire-tokens` command plugin (Swift-side), alongside the JS
// `tokens.js`; these tests lock the generated values + prove the renderer actually emits them, so the
// renderer ↔ token wiring can't silently break. (A `regenerate + git diff` CI step guards staleness.)
struct WireTokensTests {
    @Test
    func `attribute tokens are data- prefixed single chars (valid HTML), unique, covering the set`() {
        #expect(WireToken.all.count == 28)
        // The generator prefixes the attribute category with `data-` (valid HTML5 custom data attributes).
        #expect(WireToken.all.allSatisfy { $0.token.hasPrefix("data-") && $0.token.count == 6 })
        #expect(Set(WireToken.all.map(\.token)).count == 28)  // all distinct
        // A few anchors (mirrors wire-tokens.json + the data- prefix).
        #expect(WireToken.island == "data-a")
        #expect(WireToken.id == "data-b")
        #expect(WireToken.on == "data-c")
        #expect(WireToken.bind == "data-e")
        #expect(WireToken.classToggle == "data-f")
        #expect(WireToken.action == "data-p")
        #expect(WireToken.oob == "data-x")
        #expect(WireToken.link == "data-z")  // P7 boost
        #expect(WireToken.component == "data-0")  // Track 4 — component-scoped-asset mount root
        #expect(WireToken.scope == "data-1")  // Track 4 — CSS scope ancestor
    }

    @Test
    func `behavior + swap value tokens are bare single chars (attribute VALUES, not names)`() {
        #expect(WireBehavior.all.map(\.token) == ["a", "b", "c", "d", "e", "f", "g", "h"])
        #expect(WireSwap.all.map(\.token) == ["a", "b", "c", "d"])
        // The factories + the Swap emit use the tokens.
        #expect(Behavior.increment(CellArena().signal(0)).attributeValue == "\(WireBehavior.increment)#0#1")
        #expect(
            div {}.action(.get("/x").swap(.append)).render()
                == "<div \(WireToken.action)=\"get\" \(WireToken.url)=\"/x\" \(WireToken.swap)=\"\(WireSwap.append)\"></div>"
        )
    }

    @Test
    func `the renderer emits the generated tokens (renderer <-> WireToken wiring)`() {
        let arena = CellArena()
        let count = arena.signal(0)
        // Each assertion interpolates the WireToken constant, so it tracks the spec and proves the emit path.
        #expect(
            button { "+" }.on(.click, Behavior.increment(count)).render()
                == "<button \(WireToken.on):click=\"a#0#1\">+</button>")
        #expect(
            span { "0" }.bind(.text, to: count).render()
                == "<span \(WireToken.bind):text=\"0\">0</span>")
        #expect(
            div {}.classToggle("x", when: CellID(1)).render()
                == "<div \(WireToken.classToggle)=\"x:1\"></div>")
        #expect(
            input().model(CellID(2)).render() == "<input \(WireToken.model)=\"2\">")
    }

    @Test
    func `an island root stamps the marker + id + load tokens`() {
        // Island markup is hand-written in the byte-writer (perf path); this pins it to the spec values.
        let html = Island("counter", on: .load, scope: []) { span { "x" } }.render()
        #expect(
            html == "<div \(WireToken.island) \(WireToken.id)=\"counter\" \(WireToken.on)=\"load\"><span>x</span></div>"
        )
    }
}
