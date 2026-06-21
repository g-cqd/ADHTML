import ADHTML
import Testing

// The `$state` authoring surface: `@State`'s projection `$qty` (the Signal handle), value-returning
// operators (`$qty > 0` reads as Bool), the body-parse `@Bound` (`: Bool`, not `: Reactive<Bool>`), and the
// `.increment($qty)` leading-dot behavior. Reactive conditionals use `When(<name>Computed)` — a Swift `if`
// is evaluated eagerly server-side, so it cannot be client-reactive.

@Component
struct ProductRow {
    @State var qty = 0
    @Bound var inCart: Bool { $qty > 0 }  // body-parse: value-typed, macro builds the wire formula

    var body: some HTML {
        div {
            button { "+" }.on(.click, .increment($qty))  // $qty projection + leading-dot behavior
            span { String(qty) }.bind(.text, to: $qty)  // bind to the projection
            When(inCartComputed) { button { "Remove" } }  // reactive conditional via the @Bound handle
        }
    }
}

@Component
struct Totals {
    @State var apples = 2
    @State var oranges = 3
    @Bound var total: Int { $apples + $oranges }  // body-parse arithmetic

    var body: some HTML {
        output { String(apples + oranges) }.bind(.text, to: totalComputed)
    }
}

struct V2AuthoringTests {
    @Test
    func `the $state target snippet renders + wires end to end`() throws {
        let arena = CellArena()
        let html = String(decoding: try ProductRow().renderHydratable(arena: arena), as: UTF8.self)

        // qty -> cell 0 (signal), inCart -> cell 1 (the body-parse computed, value 0 > 0 = false).
        #expect(arena.cells.count == 2)
        #expect(arena.cells[0].value == .int(0))
        guard case .computed(let deps, let expr) = arena.cells[1].kind else {
            Issue.record("inCart should be a computed")
            return
        }
        #expect(arena.cells[1].value == .bool(false))
        #expect(deps == [CellID(0)])  // inCart depends on qty
        #expect(expr != nil)  // client-recomputable formula

        // `.increment($qty)` lowers to the same wire as `Behavior.increment` (a#cell#step).
        #expect(html.contains(#"data-c:click="a#0#1""#))
        // `.bind(.text, to: $qty)` binds the span to qty's cell.
        #expect(html.contains(#"<span data-e:text="0">0</span>"#))
        // `When(inCartComputed)` lowers to an inert `<template data-…if="1">` over the @Bound cell.
        #expect(html.contains(##"<template data-h="1"><button>Remove</button></template>"##))
    }

    @Test
    func `the body-parse @Bound serializes the rewritten formula ($qty > 0)`() throws {
        let html = String(decoding: try ProductRow().renderHydratable(arena: CellArena()), as: UTF8.self)
        // inCart = cmp depending on cell 0, value false, formula `cell(0) > 0` — the `>` is escaped (for
        // safe inline-script embedding) to a backslash-u003e sequence.
        let gt = "\u{5C}u003e"  // the literal 6 chars `>` as emitted in the wire
        #expect(html.contains(#"{"$":"cmp","d":[0],"v":false,"e":{"o":"\#(gt)","l":{"c":0},"r":{"i":0}}}"#))
    }

    @Test
    func `body-parse arithmetic ($apples + $oranges) computes + serializes`() throws {
        let arena = CellArena()
        let html = String(decoding: try Totals().renderHydratable(arena: arena), as: UTF8.self)
        // apples=cell0(2), oranges=cell1(3), total=cell2(cmp, 5). The dep list is [1,0] — the iterative
        // cellRefs walk pops the formula's right operand first.
        #expect(arena.cells.count == 3)
        #expect(arena.cells[2].value == .int(5))
        #expect(html.contains(#"{"$":"cmp","d":[1,0],"v":5,"e":{"o":"+","l":{"c":0},"r":{"c":1}}}"#))
    }
}
