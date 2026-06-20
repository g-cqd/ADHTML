import Testing

import ADHTMLCore  // the `Action` STRUCT (`.action(.post(…))`) + form/.render
import ADServeCore  // ResponseContent
import ADServeDSL  // StorageContext

@testable import ADHTMLActions  // the `@Action` MACRO

// RFC-0020 Track 3 P3 — the naming spike: prove `@Action` (a macro, attribute position) and `Action` (a
// struct, type position) coexist when both are imported into one file. The handler below uses the macro;
// the assertion uses the struct. If this compiles + runs, the shared name is safe.
enum SpikeActions {
    @Action("spike.delete", into: "parts")
    static func deleteThing(_ ctx: StorageContext) throws -> ResponseContent { .notFound }
}

/// A namespace whose `@Action` handlers are collected by `@Actions` into the boot registry `all`.
@Actions
enum CollectedActions {
    @Action("a.one", into: "r1")
    static func one(_ ctx: StorageContext) throws -> ResponseContent { .notFound }

    @Action("a.two", into: "r2", page: "/two")
    static func two(_ ctx: StorageContext) throws -> ResponseContent { .notFound }
}

@Suite struct ActionMacroSpikeTests {
    @Test func `the @Action macro and the Action struct coexist in one file`() {
        // The macro generated the typed handle from `@Action` (id from the slug, region from `into:`):
        #expect(SpikeActions.deleteThingAction.id == ActionID(slug: "spike.delete"))
        #expect(SpikeActions.deleteThingAction.region == "parts")
        // …and the client `Action` STRUCT still resolves in the same file (attribute vs type lookup):
        #expect(form {}.action(.post("/x")).render().contains(#"data-p="post""#))
    }

    @Test func `@Actions collects its @Action funcs into the boot registry`() {
        #expect(CollectedActions.all.count == 2)
        #expect(CollectedActions.all.map(\.id) == [ActionID(slug: "a.one"), ActionID(slug: "a.two")])
        #expect(CollectedActions.all[0].returnPath == nil)  // no `page:` -> nil (no-JS falls back)
        #expect(CollectedActions.all[1].returnPath == "/two")  // explicit `page:`
        #expect(CollectedActions.oneAction.region == "r1")  // the @Action peer handle, alongside `all`
    }
}
