import ADHTML
import Testing

// The generic, app-agnostic component vocabulary (Pill / SearchField / SegmentedControl): an author composes
// THESE instead of hand-writing `<span class="pill">`, the live-search `data-adh-*` attributes, or the
// button + behavior + active-state wiring. None know anything about a specific app.

@Component
struct DensityHost {  // a host island that OWNS the selection signal the SegmentedControl drives
    @State var density = "comfortable"
    var body: some HTML {
        div {
            SegmentedControl(
                selection: $density,
                segments: [.init("comfortable", "Comfortable"), .init("compact", "Compact")])
            div { "grid" }.classToggle("compact", when: $density.reactive == "compact")
        }
    }
}

struct GenericComponentsTests {
    @Test func `Pill renders a toned span and nothing else`() throws {
        #expect(Pill("Active", tone: .positive).render() == #"<span class="pill pill-positive">Active</span>"#)
        #expect(Pill("Obsolete").render() == #"<span class="pill pill-neutral">Obsolete</span>"#)
    }

    @Test func `SearchField is a GET form with the live-search action and no hand-written script`() throws {
        let html = SearchField(name: "q", submitsTo: "/parts", morphing: "results").render()
        #expect(html.contains(#"<form method="get" action="/parts" class="searchfield">"#))
        #expect(html.contains(#"type="search""#))
        #expect(html.contains(#"name="q""#))
        #expect(html.contains("data-p"))  // the RFC-0019 action verb attribute
        #expect(html.contains("data-u"))  // the morph target
        #expect(!html.contains("ADH.mount"))
    }

    @Test func `SegmentedControl wires selection + active state and hydrates with no script`() throws {
        let arena = CellArena()
        let html = String(decoding: try DensityHost().renderHydratable(arena: arena), as: UTF8.self)
        // density signal + two per-segment active computeds + the grid's classToggle — all serialized via the
        // ownership bubble (the SegmentedControl is a nested non-island helper).
        #expect(arena.cells.count >= 3)
        #expect(html.contains("seg-btn"))
        #expect(html.contains("data-c:click"))  // .set(selection, to:) per segment
        #expect(html.contains("data-f"))  // active-state classToggle
        #expect(!html.contains("ADH.mount"))  // composed from primitives, no hand-written widget script
    }
}
