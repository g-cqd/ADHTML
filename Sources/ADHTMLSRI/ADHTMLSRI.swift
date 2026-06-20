// ADHTMLSRI (gated `ADHTML_SRI`) — Subresource Integrity hashing for the client runtime asset
// (ADR-0006/0011). SHA-256 via swift-crypto is required *only* here; island/cache IDs use the
// non-cryptographic `ADFCore.XXH64`. The output is a standard SRI token, `sha256-<base64>`, ready for
// `<script integrity="…">`. Foundation-free: bytes feed swift-crypto via an unsafe buffer pointer, and
// the digest is base64-encoded through the shared `ADFCore.Base64` codec (standard alphabet, padded —
// the exact form SRI mandates), so the family has one base64 implementation rather than a local copy.
internal import ADFCore
internal import Crypto

/// Subresource-Integrity hashing of the client runtime (ADR-0006/0011).
public enum ADHTMLSRI {
    /// The SRI `integrity` attribute value for `bytes`: `"sha256-<base64(SHA-256(bytes))>"`.
    public static func integrity(for bytes: [UInt8]) -> String {
        "sha256-" + sha256Base64(bytes)
    }

    /// The SRI `integrity` value for a UTF-8 string (e.g. the minified runtime source).
    public static func integrity(forUTF8 text: String) -> String {
        integrity(for: Array(text.utf8))
    }

    /// The base64-encoded SHA-256 digest of `bytes` (the payload of an `sha256-…` SRI token).
    public static func sha256Base64(_ bytes: [UInt8]) -> String {
        var hasher = SHA256()
        bytes.withUnsafeBytes { buffer in hasher.update(bufferPointer: buffer) }
        return Base64.encodedString(Array(hasher.finalize()))
    }
}
