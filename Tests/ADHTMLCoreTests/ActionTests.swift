import Testing

@testable import ADHTMLCore

// RFC-0019 §6.3-F acceptance: the `Action` DSL lowers to the exact `data-adh-*` wire (contract C3). Each
// case asserts the emitted attributes match the spec verbatim, so the Swift authoring side and the
// runtime interpreter (`action.js`) agree on the wire.
struct ActionTests {
    @Test
    func `live-search action emits the RFC wire verbatim (example A)`() {
        // RFC-0019 §3.1 / §4.A — input fetches a filtered fragment and morphs the target tbody.
        #expect(
            input().attribute("name", "search")
                .action(
                    .get("/parts/rows").trigger(.input).debounce(.milliseconds(200)).target("parts-rows")
                )
                .render()
                == #"<input name="search" data-adh-action="get" data-adh-url="/parts/rows" "#
                + #"data-adh-trigger="input" data-adh-debounce="200" data-adh-target="parts-rows" "#
                + #"data-adh-swap="morph">"#
        )
    }

    @Test
    func `swap defaults to morph and is emitted explicitly`() {
        #expect(
            div { "x" }.action(.get("/x")).render()
                == #"<div data-adh-action="get" data-adh-url="/x" data-adh-swap="morph">x</div>"#
        )
    }

    @Test
    func `include serializes comma-joined; swap modes lower to their raw value`() {
        #expect(
            input().action(.get("/manufacturers/options").include("q", "kind").swap(.append).target("opts"))
                .render()
                == #"<input data-adh-action="get" data-adh-url="/manufacturers/options" "#
                + #"data-adh-include="q,kind" data-adh-target="opts" data-adh-swap="append">"#
        )
    }

    @Test
    func `optimistic lowers a Behavior invocation (example C: optimistic delete)`() {
        let arena = CellArena()
        let pending = arena.signal(false)
        #expect(
            button { "remove" }
                .action(
                    .delete("/parts/1/manufacturers/2").target("mfr-chips").optimistic(Behavior.toggle(pending))
                )
                .render()
                == #"<button data-adh-action="delete" data-adh-url="/parts/1/manufacturers/2" "#
                + #"data-adh-target="mfr-chips" data-adh-swap="morph" data-adh-optimistic="toggle#0">remove</button>"#
        )
    }

    @Test
    func `inline auto-save uses change + out-of-band swap (example D)`() {
        #expect(
            input().action(.post("/parts/1").trigger(.change).swap(.outOfBand)).render()
                == #"<input data-adh-action="post" data-adh-url="/parts/1" "#
                + #"data-adh-trigger="change" data-adh-swap="outOfBand">"#
        )
    }

    @Test
    func `debounce converts a Duration to whole milliseconds`() {
        #expect(
            input().action(.get("/x").debounce(.seconds(1))).render()
                == #"<input data-adh-action="get" data-adh-url="/x" data-adh-debounce="1000" data-adh-swap="morph">"#
        )
        #expect(Action.get("/x").debounce(.milliseconds(150)).debounceMilliseconds == 150)
        #expect(Action.get("/x").debounceMilliseconds == nil)
    }

    @Test
    func `the closed verb set mirrors ACTION_METHODS in action.js`() {
        // Parity: keep this list identical to `ACTION_METHODS` in ClientRuntime/src/action.js.
        #expect(Action.methods == ["get", "post", "put", "patch", "delete"])
        #expect(Action.get("/x").method == "get")
        #expect(Action.post("/x").method == "post")
        #expect(Action.put("/x").method == "put")
        #expect(Action.patch("/x").method == "patch")
        #expect(Action.delete("/x").method == "delete")
    }

    @Test
    func `every verb lowers to its data-adh-action token (exhaustive)`() {
        let cases: [(Action, String)] = [
            (.get("/p"), "get"), (.post("/p"), "post"), (.put("/p"), "put"),
            (.patch("/p"), "patch"), (.delete("/p"), "delete")
        ]
        for (action, verb) in cases {
            #expect(div {}.action(action).render().contains(##"data-adh-action="\##(verb)""##))
        }
    }

    @Test
    func `every swap mode lowers to its raw value (exhaustive)`() {
        // The matrix is small and closed — assert each mode independently so a mis-mapped case (e.g.
        // outOfBand emitting "oob") fails, not just the default.
        let modes: [(Swap, String)] = [
            (.morph, "morph"), (.innerHTML, "innerHTML"), (.append, "append"), (.outOfBand, "outOfBand")
        ]
        for (mode, raw) in modes {
            #expect(div {}.action(.get("/p").swap(mode)).render().contains(##"data-adh-swap="\##(raw)""##))
        }
    }
}
