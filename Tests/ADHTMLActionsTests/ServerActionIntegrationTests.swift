import ADHTMLCore  // div / form / button / .render
import ADHTMLServe  // ctx.view (the dual-mode page/fragment render a handler returns)
import ADServeCore  // ResponseContent
import ADServeDSL  // StorageContext
import Testing

@testable import ADHTMLActions

// RFC-0020 Track 3 P4 (proof) — a spare-parts-SHAPED mini-app that composes the WHOLE authoring API at once:
// the `@Actions` registry, the boot dispatch route, the ambient-signed `.submits` call site, and the
// mint→resolve verification chain. `PartActions.deletePart` mirrors the app's `formDeletePart` (read the
// form id, mutate, re-render the list region), so this doubles as the migration recipe.
//
// What this CANNOT exercise here: the live HTTP round-trip that actually runs the handler against a real
// `StorageContext` — that needs ADServe's `Loopback` test harness, which is internal to ADServe's own test
// target (not a cross-package product). The dispatcher's decision is proven via `resolve` below; running the
// handler end-to-end is the separate app-migration milestone (the app adopts the `ADHTMLActions` product +
// the macro/native build).
@Actions
enum PartActions {
    /// Mirrors the spare-parts `formDeletePart`: read the part id, delete it, re-render the parts-list region.
    @Action("part.delete", into: "parts-list", page: "/parts")
    static func deletePart(_ ctx: StorageContext) throws -> ResponseContent {
        let id = ctx.form().int("id")  // a real handler calls repo.deletePart(id:) here
        _ = id
        return try ctx.view(page: { div { "parts page" } }, fragment: { div { "rows" } })
    }
}

@Suite struct ServerActionIntegrationTests {
    private func signer() throws -> ActionSigner {
        try ActionSigner(secret: [UInt8](repeating: 0x55, count: 32))
    }

    @Test func `the @Actions registry composes into a dispatch route (one-line boot wiring)`() throws {
        let table = ServerActionTable(PartActions.all)
        _ = table.dispatchRoute(signer: try signer(), now: { 1000 })  // compiles + constructs the route
        #expect(PartActions.all.count == 1)
        #expect(PartActions.all[0].id == ActionID(slug: "part.delete"))
        #expect(PartActions.all[0].returnPath == "/parts")  // the no-JS PRG target from `page:`
    }

    @Test func `the call site renders the signed, dual-world delete form`() throws {
        let signer = try signer()
        let id = PartActions.deletePartAction.id
        let html = ActionRenderContext.$current.withValue(
            ActionRenderContext.Signing(signer: signer, sessionCookie: "abc123.tag", now: 1000)
        ) {
            form { button { "Delete" }.attribute("type", "submit") }
                .submits(to: PartActions.deletePartAction, values: ["id": "7"])
                .render()
        }
        #expect(html.contains("action=\"/_adh/act/\(id.raw)\""))  // native no-JS POST target
        #expect(html.contains(#"data-u="parts-list""#))  // the RFC-0019 morph target (the Region)
        #expect(html.contains(#"<input type="hidden" name="id" value="7">"#))  // the value field
        #expect(html.contains(#"name="_adh" value=""#))  // the signed token
    }

    @Test func `a token minted at the call site passes the dispatcher's verification`() throws {
        let signer = try signer()
        let table = ServerActionTable(PartActions.all)
        let id = PartActions.deletePartAction.id
        // What the ambient signer mints in the form (same params), then what the dispatch route checks:
        let token = signer.mint(id: id.raw, ttl: 300, sessionCookie: "abc123.tag", now: 1000)
        #expect(
            table.resolve(pathID: id.raw, token: token, sessionCookie: "abc123.tag", now: 1100, signer: signer)
                == .run(id))
        // A cross-session replay of that token is rejected (CSRF binding):
        #expect(
            table.resolve(pathID: id.raw, token: token, sessionCookie: "other.tag", now: 1100, signer: signer)
                == .forbidden("csrf"))
    }
}
