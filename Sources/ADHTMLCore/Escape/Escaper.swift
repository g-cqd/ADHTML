// Context-aware, escape-by-default output encoding (ADR-0003). The hot loop scans UTF-8 bytes and
// copies safe runs verbatim, emitting an entity only for the rare escapable byte. ADHTML ships the
// `.text` and `.attribute` encoders, a real `.url` scheme-allowlist, and `escapeScriptJSON` for the
// inline hydration state block; the `.css`/`.scriptJSON` *value* contexts route through the
// conservative attribute encoder as a fail-safe stub (over-escape, never under-escape) until their
// dedicated value encoders land — see ADR-0003.

/// Escapes interpolated values per ``EscapeContext`` into an ``HTMLByteSink``.
public enum Escaper {
    /// Emit `value` escaped for `context`.
    public static func write(_ value: String, context: EscapeContext, into sink: inout some HTMLByteSink) {
        switch context {
            case .text:
                writeEscaped(value, into: &sink, escapeQuotes: false)
            case .attribute:
                writeEscaped(value, into: &sink, escapeQuotes: true)
            case .url:
                writeURL(value, into: &sink)
            case .css, .scriptJSON:
                // Fail-safe stub: over-escape via the attribute encoder until the dedicated CSS / JSON
                // value encoders land (ADR-0003). Never under-escapes, so it cannot introduce an XSS
                // gap. The inline state block uses `escapeScriptJSON(_:)` below, not this path.
                writeEscaped(value, into: &sink, escapeQuotes: true)
        }
    }

    /// HTML-entity-escape `value`. Always escapes `& < >`; also `" '` when `escapeQuotes` (attributes).
    static func writeEscaped(_ value: String, into sink: inout some HTMLByteSink, escapeQuotes: Bool) {
        var copy = value
        copy.withUTF8 { buffer in
            for byte in buffer {
                switch byte {
                    case 0x26: sink.writeStatic("&amp;")  // &
                    case 0x3C: sink.writeStatic("&lt;")  // <
                    case 0x3E: sink.writeStatic("&gt;")  // >
                    case 0x22 where escapeQuotes: sink.writeStatic("&quot;")  // "
                    case 0x27 where escapeQuotes: sink.writeStatic("&#39;")  // '
                    default: sink.writeByte(byte)
                }
            }
        }
    }

    /// Emit a URL attribute value: reject a dangerous scheme (neutralize to `#`), else escape it.
    static func writeURL(_ value: String, into sink: inout some HTMLByteSink) {
        if URLScheme.isSafe(value) {
            writeEscaped(value, into: &sink, escapeQuotes: true)
        } else {
            sink.writeByte(0x23)  // "#": an inert placeholder, never the dangerous URL
        }
    }

    /// Escape already-formed JSON bytes for safe embedding in
    /// `<script type="application/adh-state+json">…</script>` (ADR-0003/0007): `<`/`>`/`&` →
    /// `\uXXXX` (prevents `</script>` / `<!--` breakout) and U+2028/U+2029 → `\uXXXX` (avoids JS
    /// line-terminator hazards). Every substitution is itself valid JSON, so the payload still parses.
    public static func escapeScriptJSON(_ json: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(json.count + 16)
        var index = 0
        while index < json.count {
            let byte = json[index]
            switch byte {
                case 0x3C: out.append(contentsOf: Self.escLT)  // <
                case 0x3E: out.append(contentsOf: Self.escGT)  // >
                case 0x26: out.append(contentsOf: Self.escAmp)  // &
                case 0xE2
                where index + 2 < json.count && json[index + 1] == 0x80 && json[index + 2] == 0xA8:
                    out.append(contentsOf: Self.escLS)  // U+2028
                    index += 3
                    continue
                case 0xE2
                where index + 2 < json.count && json[index + 1] == 0x80 && json[index + 2] == 0xA9:
                    out.append(contentsOf: Self.escPS)  // U+2029
                    index += 3
                    continue
                default: out.append(byte)
            }
            index += 1
        }
        return out
    }

    private static let escLT = Array("\\u003c".utf8)
    private static let escGT = Array("\\u003e".utf8)
    private static let escAmp = Array("\\u0026".utf8)
    private static let escLS = Array("\\u2028".utf8)
    private static let escPS = Array("\\u2029".utf8)
}
