import ADHTML
import Testing

struct UmbrellaTests {
    @Test
    func `the re-exported DSL renders through the umbrella module`() {
        #expect(p { "x" }.render() == "<p>x</p>")
    }

    @Test
    func `HTMLDocument prefixes a doctype`() {
        #expect(HTMLDocument { div { "hi" } }.render() == "<!doctype html><div>hi</div>")
    }

    @Test
    func `the wire-format version is exposed`() {
        #expect(ADHTMLCore.wireFormatVersion == 1)
    }
}
