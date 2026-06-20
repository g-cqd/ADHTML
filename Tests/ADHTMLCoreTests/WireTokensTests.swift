import Testing

@testable import ADHTMLCore

// The shared wire-attribute vocabulary (RFC-0021 / ADR-0019). `WireToken` is GENERATED from
// `wire-tokens.json` by the `generate-wire-tokens` command plugin (Swift-side), alongside the JS
// `tokens.js`; these tests lock the generated values + prove the renderer actually emits them, so the
// renderer ↔ token wiring can't silently break. (A `regenerate + git diff` CI step guards staleness.)
struct WireTokensTests {
    @Test
    func `the generated tokens are single-char, unique, and cover the closed set`() {
        #expect(WireToken.all.count == 24)
        #expect(WireToken.all.allSatisfy { $0.token.count == 1 })  // maximal density: 1 char each
        #expect(Set(WireToken.all.map(\.token)).count == 24)  // all distinct
        // A few anchors (mirrors wire-tokens.json).
        #expect(WireToken.island == "a")
        #expect(WireToken.id == "b")
        #expect(WireToken.on == "c")
        #expect(WireToken.bind == "e")
        #expect(WireToken.classToggle == "f")
        #expect(WireToken.action == "p")
        #expect(WireToken.oob == "x")
    }

    @Test
    func `the renderer emits the generated tokens (renderer <-> WireToken wiring)`() {
        let arena = CellArena()
        let count = arena.signal(0)
        // Each assertion interpolates the WireToken constant, so it tracks the spec and proves the emit path.
        #expect(
            button { "+" }.on(.click, Behavior.increment(count)).render()
                == "<button \(WireToken.on):click=\"increment#0#1\">+</button>")
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
