import Testing

@testable import ADHTMLCore

// RFC-0019 §6.3-H: a declarative SSE subscription lowers to `d` on the island root, which
// the runtime auto-`connect()`s on hydrate. The absence of `connect:` must stay byte-identical to before
// (the implicit-island and existing island output is unchanged), so live updates are purely additive.
struct IslandConnectTests {
    @Test
    func `Island(connect:) emits d on the island root`() {
        #expect(
            Island("parts-rows", connect: "/parts/stream") { span { "rows" } }.render()
                == #"<div a b="parts-rows" c="load" "#
                + #"d="/parts/stream"><span>rows</span></div>"#
        )
    }

    @Test
    func `an island without connect is byte-identical to before`() {
        #expect(
            Island("isle", on: .visible) { span { "x" } }.render()
                == #"<div a b="isle" c="visible"><span>x</span></div>"#
        )
    }

    @Test
    func `connect is attribute-escaped`() {
        #expect(
            Island("i", connect: "/s?q=a&b") {}.render()
                == #"<div a b="i" c="load" d="/s?q=a&amp;b"></div>"#
        )
    }
}
