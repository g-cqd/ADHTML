internal import ADFCore

/// URL-scheme safety for the `.url` escaping context (ADR-0003). Allows relative URLs, fragments, and
/// an explicit set of safe schemes; rejects `javascript:`, `data:`, `vbscript:`, and obfuscations
/// (leading whitespace/control bytes, mixed case). Built on `ADFCore.ASCII` (no Foundation, no regex).
public enum URLScheme {
    /// `true` if `url` is safe to emit as an `href`/`src`: a relative URL/fragment, or an
    /// allowlisted absolute scheme (`http`, `https`, `mailto`, `tel`).
    public static func isSafe(_ url: String) -> Bool {
        var copy = url
        return copy.withUTF8 { buffer -> Bool in
            var index = 0
            // Skip leading whitespace / control bytes (defends `\tjavascript:` style obfuscation).
            while index < buffer.count, unsafe buffer[index] <= 0x20 { index += 1 }

            // Scan for a scheme: alphanumerics + `+`/`-`/`.` up to a ':'. Stop early at a path/query/
            // fragment delimiter — that means the URL is relative (no scheme), which is safe.
            var cursor = index
            var colon = -1
            while cursor < buffer.count {
                let byte = unsafe buffer[cursor]
                if byte == 0x3A {  // ':'
                    colon = cursor
                    break
                }
                if byte == 0x2F || byte == 0x3F || byte == 0x23 { break }  // '/', '?', '#' → relative
                let isSchemeByte =
                    ASCII.isAlphanumeric(byte) || byte == 0x2B || byte == 0x2D || byte == 0x2E
                if !isSchemeByte { break }
                cursor += 1
            }
            guard colon >= 0 else { return true }  // no scheme → relative → safe

            return unsafe schemeIsAllowed(buffer, start: index, end: colon)
        }
    }

    /// Case-insensitively compare `buffer[start..<end]` against the scheme allowlist. Allocation-free: a
    /// length dispatch then a case-folded byte compare, so an absolute-URL attribute on the render hot
    /// path no longer builds a `[UInt8]` + `String` just to `switch` over four fixed schemes.
    private static func schemeIsAllowed(
        _ buffer: UnsafeBufferPointer<UInt8>, start: Int, end: Int
    ) -> Bool {
        switch end - start {
            case 3: return unsafe matches(buffer, start, "tel")
            case 4: return unsafe matches(buffer, start, "http")
            case 5: return unsafe matches(buffer, start, "https")
            case 6: return unsafe matches(buffer, start, "mailto")
            default: return false
        }
    }

    /// Whether `buffer[start...]` equals the (already lowercase, ASCII) `scheme`, comparing each source
    /// byte case-folded — no allocation. The caller has length-matched, so `scheme.count` bytes are read.
    private static func matches(
        _ buffer: UnsafeBufferPointer<UInt8>, _ start: Int, _ scheme: StaticString
    ) -> Bool {
        scheme.withUTF8Buffer { expected in
            for offset in 0 ..< expected.count {
                let source = unsafe buffer[start + offset]
                let lower = ASCII.isUppercase(source) ? source &+ 0x20 : source
                let want = unsafe expected[offset]
                if lower != want { return false }
            }
            return true
        }
    }
}
