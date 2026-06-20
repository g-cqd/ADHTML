import Testing

@testable import ADHTMLActions

// RFC-0020 Track 3 P1 — the action-token signer. Built on `ADServeCore.HMACSigner` (whose crypto is tested
// in ADServe); these assertions pin the ADHTML token MODEL (the `id.exp.sid` payload, the full-id CSRF
// binding, integrity, the overflow-clamped expiry) and the domain label that isolates action tokens from
// session cookies.
@Suite struct ActionSignerTests {
    private func signer(_ byte: UInt8 = 0x22) throws -> ActionSigner {
        try ActionSigner(secret: [UInt8](repeating: byte, count: 32))
    }

    @Test func `mint then verify round-trips the token fields`() throws {
        let signer = try signer()
        let wire = signer.mint(id: "a3f1c2", ttl: 900, sessionCookie: "deadbeefcafe", now: 1_750_000_000)
        let token = try #require(signer.verified(wire))
        #expect(token.id == "a3f1c2")
        #expect(token.exp == 1_750_000_900)  // now + ttl
        #expect(token.sid == "deadbeefcafe")  // the FULL session id (no truncation -> collision-free)
    }

    @Test func `the CSRF binding is the session id (the cookie's pre-HMAC part), or a sentinel`() throws {
        #expect(ActionSigner.sessionBinding(of: nil) == "-")
        #expect(ActionSigner.sessionBinding(of: "") == "-")
        #expect(ActionSigner.sessionBinding(of: "abc123def") == "abc123def")  // no dot -> the whole value
        #expect(ActionSigner.sessionBinding(of: "abc123.hmactag") == "abc123")  // cookie `<id>.<hmac>` -> the id
        let signer = try signer()
        let token = try #require(signer.verified(signer.mint(id: "x", ttl: 60, sessionCookie: nil, now: 0)))
        #expect(token.sid == "-")  // session-less
    }

    @Test func `a tampered token fails integrity`() throws {
        let signer = try signer()
        let wire = signer.mint(id: "x", ttl: 60, sessionCookie: "s", now: 0)
        #expect(signer.verified("\(wire)0") == nil)  // mutated tag
        #expect(signer.verified("y\(wire.dropFirst())") == nil)  // mutated id
        #expect(signer.verified("garbage") == nil)
        #expect(signer.verified("") == nil)
    }

    @Test func `a token never verifies under a different secret (key isolation)`() throws {
        let minted = try signer(0x01).mint(id: "x", ttl: 60, sessionCookie: "s", now: 0)
        #expect(try signer(0x02).verified(minted) == nil)
    }

    @Test func `the expiry add is overflow-clamped (a hostile ttl can't trap or wrap)`() throws {
        let signer = try signer()
        let token = try #require(signer.verified(signer.mint(id: "x", ttl: Int.max, sessionCookie: nil, now: 10)))
        #expect(token.exp == Int.max)  // clamped to the max, not trapped/wrapped
    }

    @Test func `the action domain label is distinct from the session-cookie label`() {
        #expect(ActionSigner.info == "ADHTML.Actions.v1.token-signing")
        #expect(ActionSigner.info != "ADServe.Sessions.v1.cookie-signing")
    }

    @Test func `ActionToken payload round-trips through parse, rejecting malformed`() {
        let token = ActionToken(id: "a3f1c2", exp: 1_750_000_900, sid: "deadbeef")
        #expect(token.payload == "a3f1c2.1750000900.deadbeef")
        #expect(ActionToken(payload: token.payload) == token)
        #expect(ActionToken(payload: "only.two") == nil)  // wrong field count
        #expect(ActionToken(payload: "a.notint.c") == nil)  // non-integer exp
        #expect(ActionToken(payload: "a.1.") == nil)  // empty sid
        #expect(ActionToken(payload: ".1.c") == nil)  // empty id
    }
}
