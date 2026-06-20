import Testing

import ADHTMLCore  // button / .render() (MemberImportVisibility needs the defining module)
import ADServeCore  // ResponseContent for the dummy handler

@testable import ADHTMLActions

// RFC-0020 Track 3 P2 — the registry + dispatch mechanism. The security-critical part (the fail-closed
// verification ladder) is factored into `resolve`, unit-tested here WITHOUT a running server; the dispatch
// route is a thin wrapper over it. The call-site test pins the dual-world lowering (RFC-0019 `Action` +
// native form + the signed hidden field).
@Suite struct ServerActionTests {
    private func fixture() throws -> (ActionSigner, ServerActionTable, ActionID) {
        let signer = try ActionSigner(secret: [UInt8](repeating: 0x33, count: 32))
        let table = ServerActionTable([
            ServerAction(slug: "part.delete", returnPath: "/parts") { _ in .notFound }  // never called by resolve
        ])
        return (signer, table, ActionID(slug: "part.delete"))
    }

    // MARK: resolve — the fail-closed ladder

    @Test func `a valid, unexpired, session-bound token resolves to run`() throws {
        let (signer, table, id) = try fixture()
        let wire = signer.mint(id: id.raw, ttl: 900, sessionID: "sess1234", now: 1000)
        let outcome = table.resolve(
            pathID: id.raw, token: wire, sessionBinding: "sess1234", now: 1500, signer: signer)
        #expect(outcome == .run(id))
    }

    @Test func `a session-less token resolves when the request is also session-less`() throws {
        let (signer, table, id) = try fixture()
        let wire = signer.mint(id: id.raw, ttl: 900, sessionID: nil, now: 0)
        #expect(table.resolve(pathID: id.raw, token: wire, sessionBinding: nil, now: 1, signer: signer) == .run(id))
    }

    @Test func `every failure mode is fail-closed`() throws {
        let (signer, table, id) = try fixture()
        let wire = signer.mint(id: id.raw, ttl: 900, sessionID: "sess1234", now: 1000)
        // missing path id
        #expect(table.resolve(pathID: nil, token: wire, sessionBinding: "sess1234", now: 1500, signer: signer)
            == .forbidden("bad action"))
        // tampered / absent token
        #expect(table.resolve(pathID: id.raw, token: "garbage", sessionBinding: "sess1234", now: 1500, signer: signer)
            == .forbidden("bad token"))
        #expect(table.resolve(pathID: id.raw, token: nil, sessionBinding: "sess1234", now: 1500, signer: signer)
            == .forbidden("bad token"))
        // token id != path id (confused deputy)
        #expect(table.resolve(pathID: "elsewhere", token: wire, sessionBinding: "sess1234", now: 1500, signer: signer)
            == .forbidden("action mismatch"))
        // expired (now > exp = 1000 + 900)
        #expect(table.resolve(pathID: id.raw, token: wire, sessionBinding: "sess1234", now: 2000, signer: signer)
            == .forbidden("expired"))
        // CSRF: the request's session binding differs from the token's
        #expect(table.resolve(pathID: id.raw, token: wire, sessionBinding: "attacker", now: 1500, signer: signer)
            == .forbidden("csrf"))
    }

    @Test func `a valid token for an UNREGISTERED action is 404, not 403`() throws {
        let (signer, table, _) = try fixture()
        let ghost = ActionID(slug: "part.purge")  // never registered
        let wire = signer.mint(id: ghost.raw, ttl: 900, sessionID: "s", now: 0)
        #expect(table.resolve(pathID: ghost.raw, token: wire, sessionBinding: "s", now: 1, signer: signer) == .notFound)
    }

    // MARK: ActionID

    @Test func `ActionID is a stable base36 hash of the slug`() {
        #expect(ActionID(slug: "part.delete").raw == ActionID(slug: "part.delete").raw)  // deterministic
        #expect(ActionID(slug: "part.delete").raw != ActionID(slug: "part.create").raw)  // distinct slugs
        #expect(ActionID(slug: "x").raw.allSatisfy { $0.isLowercase || $0.isNumber })  // base36
        #expect(ActionID("verbatim").raw == "verbatim")  // raw passthrough
    }

    // MARK: call-site lowering

    @Test func `ServerActionForm lowers to a native form + the RFC-0019 Action + the signed field`() {
        let html = ServerActionForm(ActionID("xyz"), token: "T", target: "r") {
            button { "X" }.attribute("type", "submit")
        }.render()
        #expect(
            html == #"<form method="post" action="/_adh/act/xyz" data-p="post" data-q="/_adh/act/xyz" "#
                + #"data-u="r" data-v="a"><input type="hidden" name="_adh" value="T">"#
                + #"<button type="submit">X</button></form>"#)
    }

    // MARK: .submits(to:) — the ambient-signer call site (P3)

    @Test func `the ambient signer mints a token that the dispatcher verifies`() throws {
        let signer = try ActionSigner(secret: [UInt8](repeating: 0x44, count: 32))
        let signing = ActionRenderContext.Signing(signer: signer, sessionBinding: "sess1234", now: 1000)
        let verified = try #require(signer.verified(signing.token(for: ActionID("xyz"))))
        #expect(verified.id == "xyz")
        #expect(verified.sid8 == "sess1234")  // CSRF binding flows from the render's session
        #expect(verified.exp == 1000 + 3600)  // now + the default ttl
    }

    @Test func `submits lowers to the dual-world form with the signed token + value fields`() throws {
        let signer = try ActionSigner(secret: [UInt8](repeating: 0x44, count: 32))
        let handle = ActionHandle(id: ActionID("xyz"), region: "parts")
        let html = ActionRenderContext.$current.withValue(
            ActionRenderContext.Signing(signer: signer, sessionBinding: nil, now: 0)
        ) {
            form { button { "Go" }.attribute("type", "submit") }
                .submits(to: handle, values: ["id": "7"])
                .render()
        }
        #expect(
            html.hasPrefix(
                #"<form method="post" action="/_adh/act/xyz" data-p="post" data-q="/_adh/act/xyz" "#
                    + #"data-u="parts" data-v="a">"#))
        #expect(html.contains(#"<input type="hidden" name="id" value="7">"#))  // a value field
        #expect(html.contains(#"<input type="hidden" name="_adh" value=""#))  // the signed token (non-empty)
        #expect(html.contains(#"<button type="submit">Go</button></form>"#))
    }

    @Test func `submits outside an action render emits an empty token (fail-closed, still posts)`() {
        let html = form { button { "Go" }.attribute("type", "submit") }
            .submits(to: ActionHandle(id: ActionID("z"), region: "r"))
            .render()
        #expect(html.contains(#"<input type="hidden" name="_adh" value="">"#))  // no signer -> empty -> server rejects
        #expect(html.contains(#"action="/_adh/act/z""#))  // the native form still posts
    }
}
