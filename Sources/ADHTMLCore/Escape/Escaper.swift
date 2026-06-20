// Context-aware, escape-by-default output encoding (ADR-0003). The hot loop scans UTF-8 bytes with a
// SWAR fast-forward (8 bytes/step) over safe runs and copies each run verbatim with a single bulk
// `write`, emitting an entity only for the rare escapable byte. ADHTML ships the `.text` and
// `.attribute` HTML-entity encoders and a real `.url` scheme-allowlist; the `.css`/`.scriptJSON` *value*
// contexts route through the conservative attribute encoder as a fail-safe stub (over-escape, never
// under-escape) until their dedicated value encoders land. The inline hydration state block is escaped
// by ADJSON's HTML-safe JSON encoder (`escapeHTMLUnsafe`), not here — see `WireSerializer` (ADR-0011).
//
// The SWAR kernel lives in `ADFCore.SWAR` (the shared foundation home, also used by ADJSON's encoder).

internal import ADFCore

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
    /// A SWAR stop-mask fast-forwards over safe 8-byte words; each safe run is copied with a single bulk
    /// `write`, and an entity is emitted only at an escapable byte. Output is byte-identical to a per-byte
    /// encoder. The one unsafe op — an unaligned `UInt64` load — is bounds-proven (`index + 8 <= count`),
    /// confined to the `withUTF8` closure, and never escapes it (memory-safety checklist).
    static func writeEscaped(_ value: String, into sink: inout some HTMLByteSink, escapeQuotes: Bool) {
        var copy = value
        copy.withUTF8 { buffer in
            guard let base = buffer.baseAddress else { return }
            let count = buffer.count
            var runStart = 0
            var index = 0
            while index < count {
                // SWAR: skip whole 8-byte words with no escapable byte; jump straight to the first one.
                while index + 8 <= count {
                    let word = UInt64(littleEndian: UnsafeRawPointer(base + index).loadUnaligned(as: UInt64.self))
                    var mask = SWAR.equals(word, 0x26) | SWAR.equals(word, 0x3C) | SWAR.equals(word, 0x3E)
                    if escapeQuotes { mask |= SWAR.equals(word, 0x22) | SWAR.equals(word, 0x27) }
                    if mask == 0 {
                        index += 8
                        continue
                    }
                    index += mask.trailingZeroBitCount >> 3
                    break
                }
                guard index < count else { break }

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
