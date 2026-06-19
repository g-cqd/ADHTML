import ADHTML
import Testing

@Suite("Umbrella")
struct UmbrellaTests {
    @Test("the re-exported DSL renders through the umbrella module")
    func reexport() {
        #expect(p { "x" }.render() == "<p>x</p>")
    }

    @Test("HTMLDocument prefixes a doctype")
    func document() {
        #expect(HTMLDocument { div { "hi" } }.render() == "<!doctype html><div>hi</div>")
    }

    @Test("the wire-format version is exposed")
    func wireVersion() {
        #expect(ADHTMLCore.wireFormatVersion == 1)
    }
}
