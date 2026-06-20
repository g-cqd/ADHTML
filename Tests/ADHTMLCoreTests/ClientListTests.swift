import Testing

@testable import ADHTMLCore

// RFC-0021 P3 — a client list: `ForEach` over a `Signal<[String]>`. Lowers to a `<template
// data-adh-each="cell">ROW</template>` (the row structure with `EachText` slots) followed by the initial
// server rows from the signal's current value (the no-JS fallback). The runtime clones + morph-reconciles.
struct ClientListTests {
    @Test
    func `a client list emits the row template then the initial rows`() {
        let arena = CellArena()
        let items = arena.signal(["a", "b"])  // id 0
        #expect(
            ForEach(items) { item in li { item.text } }.render()
                == #"<template data-adh-each="0"><li><span data-adh-each-text=""></span></li></template>"#
                + #"<li><span data-adh-each-text="">a</span></li>"#
                + #"<li><span data-adh-each-text="">b</span></li>"#)
    }

    @Test
    func `a filtered client list carries data-adh-filter`() {
        let arena = CellArena()
        let items = arena.signal(["x"])  // id 0
        let query = arena.signal("")  // id 1
        #expect(
            ForEach(items, filteredBy: query) { item in li { item.text } }.render()
                == #"<template data-adh-each="0" data-adh-filter="1">"#
                + #"<li><span data-adh-each-text=""></span></li></template>"#
                + #"<li><span data-adh-each-text="">x</span></li>"#)
    }

    @Test
    func `client-list row text is escaped (XSS-safe)`() {
        let arena = CellArena()
        let items = arena.signal(["<b>"])  // id 0
        #expect(
            ForEach(items) { item in li { item.text } }.render()
                == #"<template data-adh-each="0"><li><span data-adh-each-text=""></span></li></template>"#
                + #"<li><span data-adh-each-text="">&lt;b&gt;</span></li>"#)
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
                == #"<template data-adh-each="0"><li><span data-adh-each-text=""></span></li></template>"#)
    }
}
