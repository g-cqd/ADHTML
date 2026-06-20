// Signs + verifies server-action tokens (RFC-0020 Track 3) using the shared `ADServeCore.HMACSigner` under
// a DISTINCT HKDF info, so the same app secret used for `Sessions` cookies derives an independent
// action-signing key (domain separation). Build once at boot; `Sendable`, shared across requests.

internal import ADServeCore  // HMACSigner — the shared, audited primitive (extracted from Sessions)

/// Mints + verifies signed server-action tokens. Construct it at boot with the app's signing secret (the
/// SAME `secret` given to `Sessions`); the distinct domain label derives an independent key.
public struct ActionSigner: Sendable {
    /// The HKDF context label — DISTINCT from `Sessions`' `"ADServe.Sessions.v1.cookie-signing"`, so a
    /// cookie token never verifies as an action token (and vice-versa) even under one shared secret.
    static let info = "ADHTML.Actions.v1.token-signing"

    private let hmac: HMACSigner

    /// `secret` MUST be ≥ 32 bytes (throws otherwise) — pass the app's session secret.
    public init(secret: [UInt8]) throws {
        self.hmac = try HMACSigner(secret: secret, info: Self.info)
    }

    /// Mint a wire token (`<id>.<exp>.<sid>.<tag>`) for `id`, valid for `ttl` seconds from `now`, bound to the
    /// request's `sessionCookie` for CSRF. `now` is injected (no ambient clock) so renders + tests are
    /// deterministic. The expiry add is overflow-clamped so a hostile/typo'd `ttl` can't trap the process.
    public func mint(id: String, ttl: Int, sessionCookie: String?, now: Int) -> String {
        let exp = now.addingReportingOverflow(ttl).overflow ? Int.max : now + ttl
        let token = ActionToken(id: id, exp: exp, sid: Self.sessionBinding(of: sessionCookie))
        return hmac.sign(token.payload)
    }

    /// Verify a wire token's INTEGRITY: the parsed ``ActionToken`` iff the HMAC tag verifies, else `nil`.
    /// Expiry, route-id match, and session binding are policy checks the dispatch route layers on top.
    public func verified(_ wire: String) -> ActionToken? {
        guard let payload = hmac.verify(wire) else { return nil }
        return ActionToken(payload: payload)
    }

    /// The CSRF binding for a request's `session` cookie value (`<id>.<hmac>`): the session id — the part
    /// before the cookie's `.` (pure hex, so it is `.`-free and safe in the dot-joined token payload, and
    /// full-entropy so two users can't share it) — or `-` when there is no session.
    static func sessionBinding(of sessionCookie: String?) -> String {
        guard let cookie = sessionCookie, !cookie.isEmpty else { return "-" }
        if let dot = cookie.firstIndex(of: ".") { return String(cookie[..<dot]) }
        return cookie
    }
}
