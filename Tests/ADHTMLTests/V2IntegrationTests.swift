import ADHTML
import Testing

// Integration coverage for the `$state` authoring (the property-wrapper `@State`, value operators, the
// body-parse `@Bound`, and the leading-dot behaviors), end to end through @Component → renderHydratable →
// the cell graph + wire. Formula structure is asserted via the in-memory ``WireExpr`` (robust against the
// JSON `&`/`>`-escaping); the DOM wiring via the rendered `data-*` attributes.

// MARK: - components under test

@Component
struct Stepper {
    @State var qty = 5
    var body: some HTML {
        div {
            button { "−" }.on(.click, .increment($qty, by: -1))
            span { String(qty) }.bind(.text, to: $qty)  // $qty used a 3rd time → must dedup to ONE cell
            button { "+" }.on(.click, .increment($qty))
        }
    }
}

@Component
struct Flags {
    @State var a = true
    @State var b = false
    @Bound var both: Bool { $a && $b }
    @Bound var either: Bool { $a || !$b }
    var body: some HTML {
        div { span { "x" }.show(when: bothComputed).classToggle("on", when: eitherComputed) }
    }
}

@Component
struct Greeter {
    @State var name = "world"
    @Bound var greeting: String { $name + "!" }
    var body: some HTML { span { name }.bind(.text, to: greetingComputed) }
}

@Component
struct Switch {
    @State var on = false
    @State var label = "off"
    var body: some HTML {
        button { label }.on(.click, .toggle($on)).on(.dblclick, .set($label, to: "reset"))
    }
}

@Component
struct Sum2 {
    @State var x = 4
    @Bound var doubled: Int { $x * 2 }
    @Bound var positive: Bool { $x > 0 }
    var body: some HTML {
        div { span { "" }.bind(.text, to: doubledComputed).show(when: positiveComputed) }
    }
}

// The exact component the browser e2e (`ClientRuntime/e2e/v2-authoring.spec.js`) drives. Its rendered
// bytes are pinned below and copied verbatim into the e2e fixture's `/cart` route — so the cross-language
// contract (Swift emits ⇄ JS runtime consumes) is a single source of truth: if the engine output drifts,
// `cartRowEmitsTheExactWireTheBrowserE2eDrives` fails, flagging the fixture to update.
@Component
struct CartRow {
    @State var qty = 0
    @Bound var inCart: Bool { $qty > 0 }
    var body: some HTML {
        div {
            button { "−" }.on(.click, .increment($qty, by: -1))
            span { String(qty) }.bind(.text, to: $qty)
            button { "+" }.on(.click, .increment($qty))
            When(inCartComputed) {
                button { "Remove" }.on(.click, .set($qty, to: 0))
            }
        }
    }
}

struct V2IntegrationTests {
    private func render(_ html: some HTML, _ arena: CellArena) throws -> String {
        String(decoding: try html.renderHydratable(arena: arena), as: UTF8.self)
    }

    @Test
    func `projected state dedups across reads, and .increment lowers`() throws {
        let arena = CellArena()
        let html = try render(Stepper(), arena)
        // `$qty` is read in three places (two behaviors + a binding) — it must resolve to ONE cell.
        #expect(arena.cells.count == 1)
        #expect(arena.cells[0].value == .int(5))
        // `.increment($qty, by: -1)` and `.increment($qty)` lower to `a#cell#step` on the same cell.
        #expect(html.contains(##"data-c:click="a#0#-1""##))
        #expect(html.contains(##"data-c:click="a#0#1""##))
        #expect(html.contains(#"<span data-e:text="0">5</span>"#))
    }

    @Test
    func `body-parse @Bound builds boolean formulas (&& / ||) over $state`() throws {
        let arena = CellArena()
        _ = try render(Flags(), arena)
        // a=cell0(true), b=cell1(false), both=cell2(cmp a && b = false), either=cell3(cmp a || !b = true).
        #expect(arena.cells.count == 4)
        #expect(formulaOp(arena, 2) == .and)
        #expect(arena.cells[2].value == .bool(false))  // true && false
        #expect(formulaOp(arena, 3) == .or)
        #expect(arena.cells[3].value == .bool(true))  // true || !false
    }

    @Test
    func `body-parse @Bound concatenates strings ($name + literal)`() throws {
        let arena = CellArena()
        let html = try render(Greeter(), arena)
        // name=cell0("world"), greeting=cell1(cmp "world" ++ "!" = "world!").
        #expect(arena.cells.count == 2)
        #expect(formulaOp(arena, 1) == .concat)
        #expect(arena.cells[1].value == .string("world!"))
        #expect(html.contains(#"data-e:text="1""#))  // bound to the computed cell
    }

    @Test
    func `body-parse @Bound arithmetic + comparison compute the right server value`() throws {
        let arena = CellArena()
        _ = try render(Sum2(), arena)
        #expect(arena.cells.count == 3)  // x, doubled, positive
        #expect(formulaOp(arena, 1) == .mul)
        #expect(arena.cells[1].value == .int(8))  // 4 * 2
        #expect(formulaOp(arena, 2) == .gt)
        #expect(arena.cells[2].value == .bool(true))  // 4 > 0
    }

    @Test
    func `the .toggle / .set leading-dot behaviors lower to their tokens`() throws {
        let html = try render(Switch(), CellArena())
        #expect(html.contains(##"data-c:click="b#0""##))  // toggle: behavior b on cell 0
        #expect(html.contains(##"data-c:dblclick="c#1#"##))  // set: behavior c on cell 1 (label), with a param
    }

    @Test
    func `sibling instances get distinct islands and distinct cells`() throws {
        let arena = CellArena()
        let html = try render(
            div {
                Stepper()
                Stepper()
            }, arena)
        #expect(html.contains(#"data-b="c1""#))
        #expect(html.contains(#"data-b="c2""#))
        #expect(arena.cells.count == 2)  // one qty cell per instance
    }

    @Test
    func `cartRow emits the exact wire the browser e2e drives`() throws {
        // Byte-for-byte the bytes pasted into ClientRuntime/e2e/server.js `/cart`. `>` is the JSON
        // HTML-escape of `>` (inline-script-safe); `−` is U+2212; cell 1 is the `@Bound` cmp `$qty > 0`.
        let expected = #"""
            <div data-a data-b="c1" data-c="load"><div><button data-c:click="a#0#-1">−</button><span data-e:text="0">0</span><button data-c:click="a#0#1">+</button><template data-h="1"><button data-c:click="c#0#0">Remove</button></template></div></div><script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[{"$":"sig","v":0},{"$":"cmp","d":[0],"v":false,"e":{"o":"\u003e","l":{"c":0},"r":{"i":0}}}],"islands":[{"id":"c1","on":"load","scope":[0,1]}]}</script>
            """#
        let html = try render(CartRow(), CellArena())
        #expect(html == expected)
    }

    /// The top-level binary operator of the computed cell at `index`, or `nil` if it isn't a binary formula.
    private func formulaOp(_ arena: CellArena, _ index: Int) -> BinaryOp? {
        guard case .computed(_, let expr) = arena.cells[index].kind, case .binary(let op, _, _) = expr else {
            return nil
        }
        return op
    }
}
