// ADHTMLSRI (gated `ADHTML_SRI`) — Subresource Integrity hashing for the client runtime asset
// (ADR-0006/0011). SHA-256 via swift-crypto is required *only* here; island/cache IDs use the
// non-cryptographic `ADFCore.XXH64`. The output is a standard SRI token, `sha256-<base64>`, ready for
// `<script integrity="…">`. Foundation-free: bytes feed swift-crypto via an unsafe buffer pointer, and
// the digest is base64-encoded by the small standard-alphabet encoder below (ADFCore ships Hex/percent
// coding but not base64, and SRI mandates standard base64).
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
        return base64(Array(hasher.finalize()))
    }
}

/// Standard base64 (RFC 4648, `+`/`/`, `=` padding). Small + Foundation-free; SRI requires this exact
/// alphabet. Used only on a 32-byte digest, so it is not a hot path.
private func base64(_ input: [UInt8]) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    let pad: UInt8 = 0x3D  // '='
    var out: [UInt8] = []
    out.reserveCapacity((input.count + 2) / 3 * 4)

    var index = 0
    while index + 3 <= input.count {
        let chunk = (UInt32(input[index]) << 16) | (UInt32(input[index + 1]) << 8) | UInt32(input[index + 2])
        out.append(alphabet[Int((chunk >> 18) & 0x3F)])
        out.append(alphabet[Int((chunk >> 12) & 0x3F)])
        out.append(alphabet[Int((chunk >> 6) & 0x3F)])
        out.append(alphabet[Int(chunk & 0x3F)])
        index += 3
    }

    switch input.count - index {
        case 1:
            let chunk = UInt32(input[index]) << 16
            out.append(alphabet[Int((chunk >> 18) & 0x3F)])
            out.append(alphabet[Int((chunk >> 12) & 0x3F)])
            out.append(pad)
            out.append(pad)
        case 2:
            let chunk = (UInt32(input[index]) << 16) | (UInt32(input[index + 1]) << 8)
            out.append(alphabet[Int((chunk >> 18) & 0x3F)])
            out.append(alphabet[Int((chunk >> 12) & 0x3F)])
            out.append(alphabet[Int((chunk >> 6) & 0x3F)])
            out.append(pad)
        default:
            break
    }
    return String(decoding: out, as: UTF8.self)
}
