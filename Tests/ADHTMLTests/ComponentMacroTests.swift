import ADHTML
import Testing

// End-to-end tests for `@Component` + `@State` through the umbrella + the ADHTMLMacros plugin
// (declaration -> plugin -> expansion -> behavior). The components are file-scope (extension macros
// cannot attach to nested types). Each `@State` proves a different facet: type inference from a literal,
// an explicit annotation, and that the inferred Signal type is correct (a wrong type would fail the
// `Behavior.increment`/`.toggle` call site). Build with `--build-system native` (see CONTRIBUTING).

@Component
struct MacroCounter {
    @State var count = 0  // inferred Signal<Int>

    var body: some HTML {
        Island("counter", scope: [countSignal.id]) {
            button { "+" }.on("click", Behavior.increment(countSignal))
            span { String(count) }.bind(.text, to: countSignal.id)
        }
    }
}

@Component
struct MacroToggle {
    @State var isOn: Bool = false  // explicit type -> Signal<Bool>
    @State var label = "off"  // inferred Signal<String>

    var body: some HTML {
        Island("toggle", scope: [isOnSignal.id, labelSignal.id]) {
            button { label }
                .on("click", Behavior.toggle(isOnSignal))
                .bind(.class, to: labelSignal.id)
        }
    }
}

@Suite("Component macros")
struct ComponentMacroTests {
    @Test("@Component + @State render and wire a counter end to end")
    func counter() throws {
        let arena = CellArena()
        let html = String(decoding: try MacroCounter().renderHydratable(arena: arena), as: UTF8.self)

        #expect(html.contains(#"<div data-adh-island data-adh-id="counter" data-adh-on="load">"#))
        #expect(html.contains(#"data-adh-on:click="increment#0#1""#))
        #expect(html.contains(#"<span data-adh-bind:text="0">0</span>"#))
        #expect(html.contains(#"<script type="application/adh-state+json" id="adh-state">"#))

        // The three `countSignal` reads dedup to one cell, registered in the passed arena.
        #expect(arena.cells.count == 1)
        #expect(arena.cells[0].value == .int(0))
    }

    @Test("@State carries a non-default initial value")
    func nonDefault() throws {
        let arena = CellArena()
        let html = String(decoding: try MacroCounter(count: 42).renderHydratable(arena: arena), as: UTF8.self)
        #expect(html.contains(#"<span data-adh-bind:text="0">42</span>"#))
        #expect(arena.cells[0].value == .int(42))
    }

    @Test("@State infers String and respects an explicit Bool type")
    func mixedTypes() throws {
        let arena = CellArena()
        let html = String(decoding: try MacroToggle().renderHydratable(arena: arena), as: UTF8.self)
        #expect(html.contains(#"data-adh-on:click="toggle#0""#))
        #expect(html.contains(">off</button>"))

        #expect(arena.cells.count == 2)
        #expect(arena.cells[0].value == .bool(false))  // isOn
        #expect(arena.cells[1].value == .string("off"))  // label
    }

    @Test("sibling macro components get distinct cells")
    func siblings() throws {
        let arena = CellArena()
        _ = try div {
            MacroCounter(count: 1)
            MacroCounter(count: 2)
        }
        .renderHydratable(arena: arena)
        #expect(arena.cells.count == 2)
        #expect(arena.cells[0].value == .int(1))
        #expect(arena.cells[1].value == .int(2))
    }
}
