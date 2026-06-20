import ADTestKit
import Testing

@testable import ADHTMLCore

// RFC-0020 Tier-1 §1: `ForEach` must be a true alias — byte-identical to the builder `for` loop — and
// stay non-recursive (the engine's no-recursion stance) over large sequences.
struct ForEachTests {
    @Test
    func `ForEach is byte-identical to an inline builder for-loop`() {
        let data = [1, 2, 3]
        let viaForEach = div { ForEach(data) { number in span { "\(number)" } } }.render()
        let viaLoop = div {
            for number in data { span { "\(number)" } }
        }
        .render()
        #expect(viaForEach == viaLoop)
        #expect(viaForEach == "<div><span>1</span><span>2</span><span>3</span></div>")
    }

    @Test
    func `ForEach over an empty sequence emits nothing`() {
        #expect(div { ForEach([Int]()) { number in span { "\(number)" } } }.render() == "<div></div>")
    }

    @Test
    func `ForEach escapes each row (escape-by-default)`() {
        #expect(
            ul { ForEach(["<x>", "a&b"]) { value in li { value } } }.render()
                == "<ul><li>&lt;x&gt;</li><li>a&amp;b</li></ul>")
    }

    @Test
    func `ForEach is non-recursive over a 5000-element sequence (no SIGBUS on a 512 KiB stack)`() {
        runOnConstrainedStack {
            let out = div { ForEach(0 ..< 5000) { _ in span { "x" } } }.render()
            #expect(out.hasPrefix("<div><span>x</span>"))
            #expect(out.hasSuffix("</span></div>"))
        }
    }
}
