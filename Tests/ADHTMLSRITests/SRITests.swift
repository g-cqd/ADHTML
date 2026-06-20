import Testing

@testable import ADHTMLSRI

// Validated against the canonical SHA-256 test vectors (the empty string and "abc"), whose base64
// digests are the well-known SRI/CSP examples — so these pin both the swift-crypto digest and the
// hand-rolled standard-base64 encoder. Gated `ADHTML_SRI` (swift-crypto), run by the `sri` CI job.
@Suite("SRI")
struct SRITests {
    @Test("empty input matches the canonical SHA-256 base64")
    func empty() {
        #expect(ADHTMLSRI.sha256Base64([]) == "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=")
        #expect(ADHTMLSRI.integrity(for: []) == "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=")
    }

    @Test("\"abc\" matches the canonical SHA-256 base64")
    func abc() {
        #expect(ADHTMLSRI.integrity(forUTF8: "abc") == "sha256-ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=")
    }

    @Test("a SHA-256 SRI token is always sha256- + 44 base64 chars (one '=' pad)")
    func shape() {
        let token = ADHTMLSRI.integrity(forUTF8: "the quick brown fox")
        #expect(token.hasPrefix("sha256-"))
        let payload = token.dropFirst("sha256-".count)
        #expect(payload.count == 44)
        #expect(payload.hasSuffix("="))
    }

    @Test("the digest is stable across calls and byte/UTF-8 entry points agree")
    func stability() {
        let bytes = Array("adh-runtime".utf8)
        #expect(ADHTMLSRI.integrity(for: bytes) == ADHTMLSRI.integrity(forUTF8: "adh-runtime"))
        #expect(ADHTMLSRI.sha256Base64(bytes) == ADHTMLSRI.sha256Base64(bytes))
    }
}
