// Context-aware, escape-by-default output encoding (ADR-0003). The hot loop scans UTF-8 bytes and
// copies safe runs verbatim, emitting an entity only for the rare escapable byte. Tier C ships the
// `.text` and `.attribute` encoders and a real `.url` scheme-allowlist; `.css`/`.scriptJSON` route
// through the conservative attribute encoder as a *fail-safe* stub (over-escape, never under-escape)
// until their dedicated encoders land — see ADR-0003.

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
                // encoders land (ADR-0003). Never under-escapes, so it cannot introduce an XSS gap.
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
}
