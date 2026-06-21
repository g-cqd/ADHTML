import ADHTML
import Testing

// End-to-end tests for `@Bound` through the umbrella + the ADHTMLMacros plugin (declaration -> plugin ->
// expansion -> behavior). `@Bound var x: Reactive<T> { … }` adds a peer `xComputed: Computed<T>` that
// registers the author's `Reactive` expression as a CLIENT-RECOMPUTABLE computed cell — it serializes a
// `WireExpr` (`e`), so the browser re-derives it with no server round-trip (RFC-0005 §3.5 / ADR-0015
// Phase D, the rename of `@Derived`). A `@Bound` member alone makes the component an island. Components
// are file-scope (extension macros cannot attach to nested types). Build with `--build-system native`.

@Component
struct BoundDouble {
    @State var count = 3
    @Bound var doubled: Reactive<Int> { $count.reactive * 2 }  // peer: doubledComputed: Computed<Int>

    var body: some HTML {
        span { String(count) }.bind(.text, to: doubledComputed)
    }
}

@Component
struct BoundFlagOnly {
    // A `@Bound`-only component (no `@State`): a constant reactive, so the getter references no instance
    // member — still flips `isIsland` and still registers a `cmp` cell in the inferred scope.
    @Bound var visible: Reactive<Bool> { true }

    var body: some HTML {
        span { "hi" }.show(when: visibleComputed)
    }
}

struct BoundMacroTests {
    /// The exact inline-state JSON between the `adh-state` script tags (a `.contains` would survive a key
    /// reorder or a wrong value elsewhere). `firstRange(of:)` is stdlib (Foundation-free).
    private static func inlineStatePayload(_ html: String) throws -> String {
        let open = #"<script type="application/adh-state+json" id="adh-state">"#
        let start = try #require(html.firstRange(of: open))
        let rest = html[start.upperBound...]
        let end = try #require(rest.firstRange(of: "</script>"))
        return String(rest[..<end.lowerBound])
    }

    @Test
    func `@Bound emits a Computed handle that registers a client-recomputable cell`() throws {
        let arena = CellArena()
        let html = String(decoding: try BoundDouble().renderHydratable(arena: arena), as: UTF8.self)

        // count -> cell 0 (signal), doubled -> cell 1 (the registered computed, value 3*2 = 6).
        #expect(arena.cells.count == 2)
        #expect(arena.cells[0].value == .int(3))
        guard case .computed(let dependencies, let expr) = arena.cells[1].kind else {
            Issue.record("cell 1 should be a computed")
            return
        }
        #expect(arena.cells[1].value == .int(6))  // server-evaluated initial value
        #expect(dependencies == [CellID(0)])  // doubled depends on count
        #expect(expr != nil)  // carries a WireExpr -> the client re-evaluates it (no SSE round-trip)
        // The bind targets the computed's cell, not a fresh one.
        #expect(html.contains(#"<span data-e:text="1">3</span>"#))
    }

    @Test
    func `the @Bound computed serializes the EXACT cmp wire (cmp + e + reindexed deps)`() throws {
        let html = String(decoding: try BoundDouble().renderHydratable(arena: CellArena()), as: UTF8.self)
        let payload = try Self.inlineStatePayload(html)
        // count = sig(3); doubled = cmp depending on cell 0, value 6, formula `cell(0) * 2`.
        #expect(
            payload == #"{"v":1,"cells":[{"$":"sig","v":3},"#
                + #"{"$":"cmp","d":[0],"v":6,"e":{"o":"*","l":{"c":0},"r":{"i":2}}}],"#
                + #""islands":[{"id":"c1","on":"load","scope":[0,1]}]}"#)
    }

    @Test
    func `a @Bound-only component is an island (isIsland flips with no @State)`() throws {
        let arena = CellArena()
        let html = String(decoding: try BoundFlagOnly().renderHydratable(arena: arena), as: UTF8.self)

        // No @State, yet the component auto-wraps as an island (the inferred scope is the one cmp cell).
        #expect(html.contains(#"<div data-a data-b="c1" data-c="load">"#))
        #expect(arena.cells.count == 1)
        guard case .computed = arena.cells[0].kind else {
            Issue.record("the @Bound cell should be a computed")
            return
        }
        #expect(arena.cells[0].value == .bool(true))
    }

    @Test
    func `a @Bound static render falls back to a throwaway arena without crashing`() {
        // No ambient context: `ADHTMLRenderContext.bound` resolves against a throwaway arena (no wiring),
        // the value still renders inline, and nothing crashes.
        let html = BoundDouble().render()
        #expect(html.contains("<span"))
        #expect(html.contains(">3</span>"))
    }
}
