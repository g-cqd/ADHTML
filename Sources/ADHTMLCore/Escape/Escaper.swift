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
internal import ADFKernels

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
    /// encoder. The unaligned word load goes through `ADFCore.loadLE64` — the family's audited, bounds-
    /// caller-proven (`index + 8 <= count`) helper — so this file holds no hand-rolled raw-pointer
    /// arithmetic; the raw view is confined to the `withUTF8` closure and never escapes it.
    static func writeEscaped(_ value: String, into sink: inout some HTMLByteSink, escapeQuotes: Bool) {
        var copy = value
        copy.withUTF8 { buffer in
            let count = buffer.count
            guard let base = buffer.baseAddress else { return }
            let raw = UnsafeRawBufferPointer(buffer)
            var runStart = 0
            var index = 0
            while index < count {
                let remaining = count - index
                if remaining >= Self.kernelEscapeMinBytes {
                    // Long safe run: SIMD fast-forward (runtime-dispatched NEON/SSE2/AVX2) to the next
                    // escapable byte — `& < >` plus `" '` in attribute context. Same set as
                    // `escapeStopMask`; `n3`/`n4` repeat `&` in text context (a harmless re-compare).
                    let quoteNeedle: UInt8 = escapeQuotes ? 0x22 : 0x26
                    let aposNeedle: UInt8 = escapeQuotes ? 0x27 : 0x26
                    index += unsafe ADFKernels.firstIndexOfAny(
                        base: base + index, count: remaining, 0x26, 0x3C, 0x3E, quoteNeedle, aposNeedle)
                } else {
                    // Short remainder: the inline 8-byte SWAR (no call overhead), exactly as before.
                    while index + 8 <= count {
                        let mask = Self.escapeStopMask(
                            unsafe raw.loadLE64(index), escapeQuotes: escapeQuotes)
                        if mask == 0 {
                            index += 8
                            continue
                        }
                        index += mask.trailingZeroBitCount >> 3
                        break
                    }
                }
                guard index < count else { break }

                let entity: StaticString?
                switch unsafe buffer[index] {
                    case 0x26: entity = "&amp;"  // &
                    case 0x3C: entity = "&lt;"  // <
                    case 0x3E: entity = "&gt;"  // >
                    case 0x22 where escapeQuotes: entity = "&quot;"  // "
                    case 0x27 where escapeQuotes: entity = "&#39;"  // '
                    default: entity = nil
                }
                if let entity {
                    if index > runStart {
                        unsafe sink.write(UnsafeBufferPointer(rebasing: buffer[runStart ..< index]))
                    }
                    sink.writeStatic(entity)
                    runStart = index + 1
                }
                index += 1
            }
            if count > runStart {
                unsafe sink.write(UnsafeBufferPointer(rebasing: buffer[runStart ..< count]))
            }
        }
    }

    /// The SWAR stop-mask: a non-zero lane (`0x80`) at each byte that needs an HTML entity — `& < >`, plus
    /// `" '` in attribute context. Unifies the per-word escapable-byte test in one place (mirrors ADJSON's
    /// `JSONOutput` factoring); `@inline(__always)` so the word loop pays no call. The `escapeQuotes`
    /// branch is loop-invariant, so this is a structural clarification, not a behavior or cost change.
    /// Minimum remaining bytes for the SIMD escape scan to beat the inline SWAR (below it the C-call
    /// overhead dominates); short interpolated values keep the branch-predictable inline path. Tune
    /// from a benchmark crossover like `UTF8Validation.simdMinBytes`.
    @usableFromInline static let kernelEscapeMinBytes = 32

    @inline(__always)
    private static func escapeStopMask(_ word: UInt64, escapeQuotes: Bool) -> UInt64 {
        let core = SWAR.equals(word, 0x26) | SWAR.equals(word, 0x3C) | SWAR.equals(word, 0x3E)
        return escapeQuotes ? core | SWAR.equals(word, 0x22) | SWAR.equals(word, 0x27) : core
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
