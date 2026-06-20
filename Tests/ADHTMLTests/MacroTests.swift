import ADHTML
import Testing

// Macros are tested behaviorally — end to end through the umbrella's public `#attr` declaration and the
// ADHTMLMacros plugin (declaration -> plugin -> expansion). A valid name expands to its literal; an
// invalid name is a compile-time error, verified by a negative compile check in CI rather than at
// runtime (ADR-0009). Build with `--build-system native` (see CONTRIBUTING).
struct MacroTests {
    @Test
    func `#attr validates and expands a valid attribute name to its literal`() {
        #expect(#attr("data-foo") == "data-foo")
        #expect(#attr("aria-label") == "aria-label")
        #expect(#attr("hx-get") == "hx-get")
    }

    @Test
    func `#attr result is usable as an element attribute name`() {
        #expect(div {}.attribute(#attr("data-id"), "x").render() == #"<div data-id="x"></div>"#)
    }
}
