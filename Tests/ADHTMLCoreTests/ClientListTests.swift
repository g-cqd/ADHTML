import Testing

@testable import ADHTMLCore

// RFC-0021 P3 — a client list: `ForEach` over a `Signal<[String]>`. Lowers to a `<template
// m="cell">ROW</template>` (the row structure with `EachText` slots) followed by the initial
// server rows from the signal's current value (the no-JS fallback). The runtime clones + morph-reconciles.
struct ClientListTests {
    @Test
    func `a client list emits the row template then the initial rows`() {
        let arena = CellArena()
        let items = arena.signal(["a", "b"])  // id 0
        #expect(
            ForEach(items) { item in li { item.text } }.render()
                == #"<template m="0"><li><span n=""></span></li></template>"#
                + #"<li><span n="">a</span></li>"#
                + #"<li><span n="">b</span></li>"#)
    }

    @Test
    func `a filtered client list carries o`() {
        let arena = CellArena()
        let items = arena.signal(["x"])  // id 0
        let query = arena.signal("")  // id 1
        #expect(
            ForEach(items, filteredBy: query) { item in li { item.text } }.render()
                == #"<template m="0" o="1">"#
                + #"<li><span n=""></span></li></template>"#
                + #"<li><span n="">x</span></li>"#)
    }

    @Test
    func `client-list row text is escaped (XSS-safe)`() {
        let arena = CellArena()
        let items = arena.signal(["<b>"])  // id 0
        #expect(
            ForEach(items) { item in li { item.text } }.render()
                == #"<template m="0"><li><span n=""></span></li></template>"#
                + #"<li><span n="">&lt;b&gt;</span></li>"#)
    }

    @Test
    func `the static ForEach stays byte-identical (no template, additive)`() {
        // Static mode (a plain Sequence) emits no template — just the inline rows, as before.
        #expect(ForEach(["a", "b"]) { item in li { item } }.render() == #"<li>a</li><li>b</li>"#)
    }

    @Test
    func `an empty client list emits only the template`() {
        let arena = CellArena()
        let items = arena.signal([String]())  // id 0
        #expect(
            ForEach(items) { item in li { item.text } }.render()
                == #"<template m="0"><li><span n=""></span></li></template>"#)
    }
}
