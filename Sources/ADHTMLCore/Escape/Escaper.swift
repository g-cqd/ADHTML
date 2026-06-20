// Context-aware, escape-by-default output encoding (ADR-0003). The hot loop scans UTF-8 bytes and
// copies safe runs verbatim with a single bulk `write`, emitting an entity only for the rare escapable
// byte. ADHTML ships the `.text` and `.attribute` HTML-entity encoders and a real `.url`
// scheme-allowlist; the `.css`/`.scriptJSON` *value* contexts route through the conservative attribute
// encoder as a fail-safe stub (over-escape, never under-escape) until their dedicated value encoders
// land. The inline hydration state block is escaped by ADJSON's HTML-safe JSON encoder
// (`escapeHTMLUnsafe`), not here — see `WireSerializer` (ADR-0003/0011).

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
                // gap. The inline state block is escaped by ADJSON's HTML-safe encoder, not this path.
                writeEscaped(value, into: &sink, escapeQuotes: true)
        }
    }

    /// HTML-entity-escape `value`. Always escapes `& < >`; also `" '` when `escapeQuotes` (attributes).
    /// Scans for runs of safe bytes and copies each run with a single bulk `write`, emitting an entity
    /// only at an escapable byte — so common (mostly-safe) text is one or two `memcpy`s, not N
    /// `writeByte`s. The output is byte-identical to a per-byte encoder.
    static func writeEscaped(_ value: String, into sink: inout some HTMLByteSink, escapeQuotes: Bool) {
        var copy = value
        copy.withUTF8 { buffer in
            let count = buffer.count
            var runStart = 0
            var index = 0
            while index < count {
                let entity: StaticString?
                switch buffer[index] {
                    case 0x26: entity = "&amp;"  // &
                    case 0x3C: entity = "&lt;"  // <
                    case 0x3E: entity = "&gt;"  // >
                    case 0x22 where escapeQuotes: entity = "&quot;"  // "
                    case 0x27 where escapeQuotes: entity = "&#39;"  // '
                    default: entity = nil
                }
                if let entity {
                    if index > runStart { sink.write(UnsafeBufferPointer(rebasing: buffer[runStart ..< index])) }
                    sink.writeStatic(entity)
                    runStart = index + 1
                }
                index += 1
            }
            if count > runStart { sink.write(UnsafeBufferPointer(rebasing: buffer[runStart ..< count])) }
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
