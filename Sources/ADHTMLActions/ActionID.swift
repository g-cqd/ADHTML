// The stable wire id of a server action (RFC-0020 Track 3): a hash of the author's slug, so the
// `/_adh/act/<id>` URL is deterministic across builds + machines (frozen-at-boot safe) and short on the
// wire, without leaking handler names. NON-cryptographic by design — the id is a routing/bucket key, not
// a secret and not an integrity boundary (the SIGNED token is the integrity boundary). Collisions are
// caught when the table is built (a duplicate id is a boot precondition failure), never silently.

internal import ADFCore  // XXH64 — the family's fast non-crypto hash

/// A server action's stable id (the `/_adh/act/<id>` path segment + the registry key).
public struct ActionID: Hashable, Sendable, CustomStringConvertible {
    public let raw: String

    /// Wrap a precomputed id (e.g. parsed from a request path).
    public init(_ raw: String) { self.raw = raw }

    /// Derive the id from an author slug: low 32 bits of `XXH64(slug)`, base36 (≤ 7 chars). Deterministic
    /// and seedless, so the same slug yields the same id everywhere — the route literal stays stable.
    public init(slug: String) {
        let hash = XXH64.hash(Array(slug.utf8)) & 0xFFFF_FFFF
        self.raw = String(hash, radix: 36)
    }

    public var description: String { raw }
}
