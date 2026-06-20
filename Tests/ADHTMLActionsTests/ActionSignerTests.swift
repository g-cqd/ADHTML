import Testing

@testable import ADHTMLActions

// RFC-0020 Track 3 P1 — the action-token signer. Built on `ADServeCore.HMACSigner` (whose crypto is tested
// in ADServe); these assertions pin the ADHTML token MODEL (the `id.exp.sid8` payload, CSRF binding, integrity)
// and the domain label that isolates action tokens from session cookies.
@Suite struct ActionSignerTests {
    private func signer(_ byte: UInt8 = 0x22) throws -> ActionSigner {
        try ActionSigner(secret: [UInt8](repeating: byte, count: 32))
    }

    @Test func `mint then verify round-trips the token fields`() throws {
        let signer = try signer()
        let wire = signer.mint(id: "a3f1c2", ttl: 900, sessionID: "deadbeefcafe", now: 1_750_000_000)
        let token = try #require(signer.verified(wire))
        #expect(token.id == "a3f1c2")
        #expect(token.exp == 1_750_000_900)  // now + ttl
        #expect(token.sid8 == "deadbeef")  // first 8 of the session id
    }

    @Test func `a session-less token binds to the sentinel`() throws {
        let signer = try signer()
        let token = try #require(signer.verified(signer.mint(id: "x", ttl: 60, sessionID: nil, now: 0)))
        #expect(token.sid8 == "-")
        #expect(ActionSigner.sid8(of: "") == "-")  // empty id is also session-less
        #expect(ActionSigner.sid8(of: "0123456789abcdef") == "01234567")  // first 8
    }

    @Test func `a tampered token fails integrity`() throws {
        let signer = try signer()
        let wire = signer.mint(id: "x", ttl: 60, sessionID: "s", now: 0)
        #expect(signer.verified("\(wire)0") == nil)  // mutated tag
        #expect(signer.verified("y\(wire.dropFirst())") == nil)  // mutated id
        #expect(signer.verified("garbage") == nil)
        #expect(signer.verified("") == nil)
    }

    @Test func `a token never verifies under a different secret (key isolation)`() throws {
        let minted = try signer(0x01).mint(id: "x", ttl: 60, sessionID: "s", now: 0)
        #expect(try signer(0x02).verified(minted) == nil)
    }

    @Test func `the action domain label is distinct from the session-cookie label`() {
        #expect(ActionSigner.info == "ADHTML.Actions.v1.token-signing")
        #expect(ActionSigner.info != "ADServe.Sessions.v1.cookie-signing")
    }

    @Test func `ActionToken payload round-trips through parse, rejecting malformed`() {
        let token = ActionToken(id: "a3f1c2", exp: 1_750_000_900, sid8: "deadbeef")
        #expect(token.payload == "a3f1c2.1750000900.deadbeef")
        #expect(ActionToken(payload: token.payload) == token)
        #expect(ActionToken(payload: "only.two") == nil)  // wrong field count
        #expect(ActionToken(payload: "a.notint.c") == nil)  // non-integer exp
        #expect(ActionToken(payload: "a.1.") == nil)  // empty sid8
        #expect(ActionToken(payload: ".1.c") == nil)  // empty id
    }
}
