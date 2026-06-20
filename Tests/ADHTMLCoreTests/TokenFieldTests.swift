import Testing

@testable import ADHTMLCore

// RFC-0021 P9 — the `TokenField` capstone, composed ENTIRELY from the closed declarative primitives (P1
// model + P3 client list + P4 keymap/commit/removeLast/commitValue + P5 filter + P6 show) with no
// hand-written JS. These assertions prove each primitive is wired into the one component (the refined-
// architecture proof) and that it lowers to the closed wire tokens.
struct TokenFieldTests {
    private func rendered() throws -> String {
        let arena = CellArena()
        let view = TokenField(name: "tags", items: ["swift", "rust"], selected: ["go"], action: "/tags")
        return try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)
    }

    @Test
    func `it auto-islands and posts to its action (no-JS form fallback)`() throws {
        let html = try rendered()
        #expect(html.contains(#"<div data-a data-b="tf1" data-c="load">"#))  // implicit island
        #expect(html.contains(#"<form action="/tags" method="post">"#))  // no-JS commit route
    }

    @Test
    func `chips are a client list over the tokens array, seeded from selected`() throws {
        let html = try rendered()
        // P3: a <template data-m="<tokens>"> + the initial chip from `selected`.
        #expect(html.contains(#"<ul class="tokens"><template data-m="1">"#))
        #expect(html.contains(#"<li class="chip"><span data-n="">go</span></li>"#))
    }

    @Test
    func `the input is two-way bound and keyboard-mapped (P1 + P4)`() throws {
        let html = try rendered()
        #expect(html.contains(#"data-i="0""#))  // .model(query) — query is cell 0
        // .keymap: Enter commits (f = commit, tokens 1, query 0); Backspace pops (g = removeLast).
        #expect(html.contains(#"data-y="Enter:f#1#0;Backspace:g#1""#))
    }

    @Test
    func `suggestions are a filtered client list, shown while typing, click-to-commit (P3 + P5 + P6 + P4)`()
        throws
    {
        let html = try rendered()
        #expect(html.contains(#"<ul class="suggestions" data-g="4"#))  // .show(when: query.count > 0)
        #expect(html.contains(#"<template data-m="3">"#))  // ForEach over the filtered computed (cell 3)
        // each suggestion commits its own text on click (h = commitValue, tokens 1, query 0).
        #expect(html.contains(##"<li data-c:click="h#1#0"><span data-n="">swift</span></li>"##))
        // P5: the filter expression is in the inline state (recomputed in-browser, no round-trip).
        #expect(html.contains(#""fl":"#))
    }

    @Test
    func `the static (no-JS) render is a plain form with no island, no bindings`() {
        // No ambient context -> the fallback form (the server `action` handles the commit).
        let html = TokenField(name: "tags", items: ["a"], action: "/t").render()
        #expect(html == #"<form action="/t" method="post"><input name="tags" type="text" autocomplete="off"></form>"#)
    }
}
