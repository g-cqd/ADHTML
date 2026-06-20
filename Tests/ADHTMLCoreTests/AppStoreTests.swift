import Testing

@testable import ADHTMLCore

// RFC-0021 P8 — `AppStore`, a document-level reactive store whose signals survive boosted (P7) navigations.
// It lowers to a stably-keyed root island (`adh-store`) holding its persistent cells; a `Link.boost` morphs
// a NESTED `Region`, never this root island or the inline state script, so the store's cells persist while
// only the morphed region resets. These assertions pin that structure (the store is a separate island from
// any boostable region); the cross-navigation persistence itself is browser-validated (dom.test.js).
struct AppStoreTests {
    @Test
    func `AppStore is a stably-keyed root island (adh-store) holding its persistent cells`() throws {
        let arena = CellArena()
        let view = AppStore { store in
            let dark = store.signal("dark", default: false)
            div { "x" }.classToggle("dark", when: dark)
        }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)
        #expect(html.hasPrefix(#"<div data-a data-b="adh-store" data-c="load">"#))
        #expect(html.contains(#"<div data-f="dark:0">x</div>"#))  // the store binding, cell 0
        #expect(html.contains(#""islands":[{"id":"adh-store","on":"load","scope":[0]}]"#))
        #expect(html.contains(#"{"$":"sig","v":false}"#))  // the persistent cell is in the wire
    }

    @Test
    func `store signals dedup by key — the same name resolves to one persistent cell`() {
        let arena = CellArena()
        let scope = StoreScope(arena: arena, scope: 0)
        let first = scope.signal("theme", default: "light")
        let second = scope.signal("theme", default: "light")
        #expect(first.id == second.id)  // same key -> same cell (read it anywhere, get the one signal)
        #expect(arena.cells.count == 1)  // not duplicated in the wire
    }

    @Test
    func `the store is a separate island from a nested Region — a region morph cannot reset it`() throws {
        let arena = CellArena()
        let view = AppStore { store in
            let dark = store.signal("dark", default: false)
            div {
                span { "off" }.bind(.text, to: dark)  // a store binding in the persistent chrome
                Region("content") { p { "home" } }  // the boost target: its own island, outside the store cells
            }
        }
        let html = try String(decoding: view.renderHydratable(arena: arena), as: UTF8.self)
        // Two distinct islands: the store (carrying the persistent cell) and the boostable region (empty scope).
        #expect(html.contains(#"{"id":"adh-store","on":"load","scope":[0]}"#))
        #expect(html.contains(#"{"id":"content","on":"load","scope":[]}"#))
        // The store binding is OUTSIDE the region, so a `getElementById("content")` morph never touches it.
        #expect(html.contains(#"<span data-e:text="0">off</span>"#))
    }

    @Test
    func `a static AppStore render inlines its body — no island, no wiring (the no-JS fallback)`() {
        let html = AppStore { _ in div { "x" } }.render()
        #expect(html == #"<div>x</div>"#)  // no ambient context -> no store island, just the content
    }
}
