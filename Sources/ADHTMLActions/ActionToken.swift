// The payload carried inside a signed server-action token (RFC-0020 Track 3). On the wire a token is the
// string `<id>.<exp>.<sid>.<tag>`: the trailing HMAC tag (appended by `ADServeCore.HMACSigner.sign`)
// authenticates the three-field payload below. All three fields are policy inputs the dispatch route reads
// to decide route-match / expiry / CSRF, so the token is signed-not-sealed — none of the fields is secret.

/// The verified payload of a server-action token.
public struct ActionToken: Equatable, Sendable {
    /// The action id (`ActionID.raw`) — also the `/_adh/act/<id>` path segment. Binds the token to ONE action.
    public let id: String
    /// Absolute expiry, seconds since the Unix epoch — the replay/lifetime bound.
    public let exp: Int
    /// CSRF binding: the bearer's FULL session id (the session cookie's pre-HMAC part — pure hex, so it is
    /// `.`-free and safe in this dot-joined payload, and full-entropy so it can't be coincidentally collided
    /// across users), or `-` when session-less. NB: a defence-in-depth layer ON TOP of the session cookie's
    /// `SameSite=Lax` (the primary CSRF control) — see ``ServerActionTable``'s `resolve`.
    public let sid: String

    public init(id: String, exp: Int, sid: String) {
        self.id = id
        self.exp = exp
        self.sid = sid
    }

    /// The canonical dot-joined string the signer signs (`"<id>.<exp>.<sid>"`). The fields are drawn from
    /// disjoint alphabets (base36 id / digits / hex-or-`-`), so the `.` join parses unambiguously.
    public var payload: String { "\(id).\(exp).\(sid)" }

    /// Parse a *verified* payload back into its fields — `nil` unless it is exactly three non-empty fields
    /// with an integer `exp`. Call only on the output of `HMACSigner.verify` (integrity is checked first).
    public init?(payload: String) {
        let parts = payload.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[2].isEmpty, let exp = Int(parts[1])
        else { return nil }
        self.id = String(parts[0])
        self.exp = exp
        self.sid = String(parts[2])
    }
}
