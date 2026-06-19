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
            while index < buffer.count, buffer[index] <= 0x20 { index += 1 }

            // Scan for a scheme: alphanumerics + `+`/`-`/`.` up to a ':'. Stop early at a path/query/
            // fragment delimiter — that means the URL is relative (no scheme), which is safe.
            var cursor = index
            var colon = -1
            while cursor < buffer.count {
                let byte = buffer[cursor]
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

            return schemeIsAllowed(buffer, start: index, end: colon)
        }
    }

    /// Case-insensitively compare `buffer[start..<end]` against the scheme allowlist.
    private static func schemeIsAllowed(
        _ buffer: UnsafeBufferPointer<UInt8>, start: Int, end: Int
    ) -> Bool {
        var lowered: [UInt8] = []
        lowered.reserveCapacity(end - start)
        var index = start
        while index < end {
            let byte = buffer[index]
            lowered.append(ASCII.isUppercase(byte) ? byte &+ 0x20 : byte)
            index += 1
        }
        let scheme = String(decoding: lowered, as: UTF8.self)
        switch scheme {
            case "http", "https", "mailto", "tel": return true
            default: return false
        }
    }
}
