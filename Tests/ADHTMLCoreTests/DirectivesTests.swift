import Testing

@testable import ADHTMLCore

// RFC-0021 P2 (class-merge) + P6 (conditional render), ADR-0017. Byte-exact lowering of the closed
// `data-adh-class` / `data-adh-show` / `data-adh-if` wire tokens the runtime interprets. The cell index in
// each token is the same raw cell id `bind`/`on` already use (one convention across the directives).
struct DirectivesTests {
    // MARK: P2 — class-merge

    @Test
    func `classToggle emits data-adh-class and merges repeated toggles`() {
        let arena = CellArena()
        let a = arena.signal(false)  // id 0
        let b = arena.signal(false)  // id 1
        #expect(
            div { "x" }.classToggle("active", when: a).render()
                == #"<div data-adh-class="active:0">x</div>"#)
        #expect(
            div { "x" }.classToggle("a", when: a).classToggle("b", when: b).render()
                == #"<div data-adh-class="a:0;b:1">x</div>"#)
    }

    @Test
    func `classToggle paints the initial class when the signal is on (no FOUC)`() {
        let arena = CellArena()
        let on = arena.signal(true)  // id 0
        #expect(
            div { "x" }.classToggle("active", when: on).render()
                == #"<div data-adh-class="active:0" class="active">x</div>"#)
        // Merges into an existing static class rather than clobbering it.
        #expect(
            div { "x" }.class("card").classToggle("active", when: on).render()
                == #"<div class="card active" data-adh-class="active:0">x</div>"#)
    }

    @Test
    func `classToggle accepts a raw CellID (no initial-class knowledge)`() {
        #expect(div {}.classToggle("x", when: CellID(3)).render() == #"<div data-adh-class="x:3"></div>"#)
    }

    // MARK: P6 — `.show(when:)` (display toggle, node stays in the DOM)

    @Test
    func `show is visible with no inline style when the signal is initially on`() {
        let arena = CellArena()
        let visible = arena.signal(true)  // id 0
        #expect(div { "x" }.show(when: visible).render() == #"<div data-adh-show="0">x</div>"#)
    }

    @Test
    func `show renders hidden (inline display none) when the signal is initially off`() {
        let arena = CellArena()
        let visible = arena.signal(false)  // id 0
        #expect(
            div { "x" }.show(when: visible).render()
                == #"<div data-adh-show="0" style="display:none">x</div>"#)
        // The display:none merges with an existing style.
        #expect(
            div { "x" }.attribute("style", "color:red").show(when: visible).render()
                == #"<div style="color:red;display:none" data-adh-show="0">x</div>"#)
    }

    // MARK: P6 — `When` (mount/unmount via an inert template)

    @Test
    func `When lowers to an inert template carrying data-adh-if`() {
        let arena = CellArena()
        let open = arena.signal(true)  // id 0
        #expect(
            When(open) { span { "hi" } }.render()
                == #"<template data-adh-if="0"><span>hi</span></template>"#)
        #expect(When(CellID(2)) { "x" }.render() == #"<template data-adh-if="2">x</template>"#)
    }

    @Test
    func `the When content is escaped inside the template (XSS-safe)`() {
        #expect(
            When(CellID(0)) { "<script>alert(1)</script>" }.render()
                == #"<template data-adh-if="0">&lt;script&gt;alert(1)&lt;/script&gt;</template>"#)
    }

    // MARK: Reactive overloads register a client-recomputable cell (inside a hydration context — the
    // ambient context a `@Component` body supplies; eager content built outside one degrades, like `bind`).

    @Test
    func `the Reactive directive overloads register client-recomputable cells in order`() {
        let arena = CellArena()
        let count = arena.signal(0)  // id 0
        let context = ADHTMLRenderContext.Context(arena: arena, scope: arena.freshScope())
        let html = ADHTMLRenderContext.$current.withValue(context) {
            div { "x" }
                .classToggle("empty", when: count.reactive == 0)  // registers cell 1, initially true
                .show(when: count.reactive > 0)  // registers cell 2, initially false
                .render()
        }
        #expect(
            html == #"<div data-adh-class="empty:1" class="empty" data-adh-show="2" "#
                + #"style="display:none">x</div>"#)
    }
}
