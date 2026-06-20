import ADHTML
import Testing

// End-to-end tests for `@Component` + `@State` through the umbrella + the ADHTMLMacros plugin
// (declaration -> plugin -> expansion -> behavior). A component with `@State` is an InteractiveComponent:
// it AUTO-WRAPS its body in a hydration island with an inferred scope, so the author writes NO `Island`,
// `scope:`, or `.id` (RFC-0005 §3.0). Components are file-scope (extension macros cannot attach to nested
// types). Build with `--build-system native` (see CONTRIBUTING).

@Component
struct MacroCounter {
    @State var count = 0  // inferred Signal<Int>

    var body: some HTML {
        div {
            button { "+" }.on(.click, Behavior.increment(countSignal))
            span { String(count) }.bind(.text, to: countSignal)
        }
    }
}

@Component
struct MacroToggle {
    @State var isOn: Bool = false  // explicit type -> Signal<Bool>
    @State var label = "off"  // inferred Signal<String>

    var body: some HTML {
        button { label }
            .on(.click, Behavior.toggle(isOnSignal))
            .bind(.class, to: labelSignal)
    }
}

struct ComponentMacroTests {
    @Test
    func `@Component + @State auto-wrap as an island and wire a counter end to end`() throws {
        let arena = CellArena()
        let html = String(decoding: try MacroCounter().renderHydratable(arena: arena), as: UTF8.self)

        // No Island/scope/.id authored — the component became an island automatically (inferred scope).
        #expect(html.contains(#"<div data-adh-island data-adh-id="c1" data-adh-on="load">"#))
        #expect(html.contains(#"data-adh-on:click="increment#0#1""#))
        #expect(html.contains(#"<span data-adh-bind:text="0">0</span>"#))
        #expect(html.contains(#"<script type="application/adh-state+json" id="adh-state">"#))

        // The three `countSignal` reads dedup to one cell, registered in the passed arena.
        #expect(arena.cells.count == 1)
        #expect(arena.cells[0].value == .int(0))
    }

    @Test
    func `@State carries a non-default initial value`() throws {
        let arena = CellArena()
        let html = String(decoding: try MacroCounter(count: 42).renderHydratable(arena: arena), as: UTF8.self)
        #expect(html.contains(#"<span data-adh-bind:text="0">42</span>"#))
        #expect(arena.cells[0].value == .int(42))
    }

    @Test
    func `@State infers String and respects an explicit Bool type`() throws {
        let arena = CellArena()
        let html = String(decoding: try MacroToggle().renderHydratable(arena: arena), as: UTF8.self)
        #expect(html.contains(#"data-adh-on:click="toggle#0""#))
        #expect(html.contains(">off</button>"))

        #expect(arena.cells.count == 2)
        #expect(arena.cells[0].value == .bool(false))  // isOn (read first, in the behavior)
        #expect(arena.cells[1].value == .string("off"))  // label (read in the binding)
    }

    @Test
    func `sibling macro components get distinct islands and distinct cells`() throws {
        let arena = CellArena()
        let html = String(
            decoding: try div {
                MacroCounter(count: 1)
                MacroCounter(count: 2)
            }
            .renderHydratable(arena: arena),
            as: UTF8.self)
        // Each instance is its own island (distinct ids), each with its own cell.
        #expect(html.contains(#"data-adh-id="c1""#))
        #expect(html.contains(#"data-adh-id="c2""#))
        #expect(arena.cells.count == 2)
        #expect(arena.cells[0].value == .int(1))
        #expect(arena.cells[1].value == .int(2))
    }
}
