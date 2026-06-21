import ADHTML
import Testing

// `ADHTMLRenderContext.shared(key:)` is the render-GLOBAL keyed signal: the same key resolves to ONE cell
// across every component, unlike `@State` / `state(key:)` (deduped per component instance). It is how two
// islands share app-level state — e.g. a topbar search input and every list row's `.show(when:)` — without
// threading a `Signal` through every initializer.

func sharedQuery() -> Signal<String> { ADHTMLRenderContext.shared(key: "q", default: "") }

@Component
struct SharedHost {  // the input lives here...
    var body: some HTML {
        div {
            input().attribute("name", "q").model(sharedQuery())
            SharedRow()
        }
    }
}

struct SharedRow: Component {  // ...and the row that reacts to it is a different component
    var body: some HTML {
        span { "row" }
            .show(when: Reactive(stringLiteral: "alpha").contains(sharedQuery().reactive.lowercased()))
    }
}

struct SharedSignalTests {
    @Test
    func `shared(key:) resolves to ONE cell across components`() throws {
        let arena = CellArena()
        let html = String(decoding: try SharedHost().renderHydratable(arena: arena), as: UTF8.self)

        // Two `sharedQuery()` calls in two components dedup to ONE signal cell (index 0); the only other cell
        // is the row's `.show` computed (index 1). Were they NOT shared, there'd be a second "" signal.
        #expect(arena.cells.count == 2)
        let signals = arena.cells.filter {
            guard case .signal = $0.kind else { return false }
            return $0.value == .string("")
        }
        #expect(signals.count == 1)  // exactly one shared query cell

        #expect(html.contains(#"data-i="0""#))  // the input two-way-binds the shared cell (index 0)
        #expect(html.contains(#"data-g="1""#))  // the cross-component row shows on the computed that reads it
    }
}
