// The shared representation behind both `Markdown` authoring surfaces (the string-interpolation form and
// the `@MarkdownBuilder` form): a Markdown SOURCE string with component SLOTS planted as Private-Use-Area
// sentinels, plus the ordered slots themselves. The sentinel trick (ADR — Markdown-in-builder): a scalar
// in U+E000…U+F8FF SURVIVES the `Escaper` (which escapes only the five ASCII bytes `& < > " '`), so a slot
// marker planted in the Markdown source passes THROUGH `ADHTMLMarkdown.render` untouched, and the rendered
// HTML can then be split on the sentinels and spliced with each slot's live render.
//
// These files import ONLY ADHTMLCore (never swift-markdown), so the `Text`/`Table`/`Image` clash that
// `ADHTMLMarkdown.swift` works around does not arise here — every bare type name resolves to ADHTMLCore.
internal import struct ADHTMLCore.ArraySink
internal import struct ADHTMLCore.DirectTarget
internal import protocol ADHTMLCore.HTML
internal import struct ADHTMLCore.HTMLProgram

/// An embedded `some HTML` captured as two TARGET-GENERIC render thunks — one per concrete `RenderTarget`
/// — built by partial application of `C._render` at the call site. This is how a slot stays type-safe
/// without `any HTML`: `HTML._render` is generic over its target (not an existential), so a heterogeneous
/// `[any HTML]` could not call it; instead each slot bakes its concrete `C` into two closures the target
/// picks between (`RenderTarget._embedMarkdownSlot`).
struct MarkdownSlot: Sendable {
    /// Render the component's ops into a materialized `HTMLProgram` (full island/hydration fidelity).
    let program: @Sendable (inout HTMLProgram) -> Void
    /// Render the component to bytes via the single-pass `DirectTarget` (the static path).
    let direct: @Sendable (inout DirectTarget<ArraySink>) -> Void

    init<C: HTML>(_ component: C) {
        program = { target in C._render(component, into: &target) }
        direct = { target in C._render(component, into: &target) }
    }
}

/// A Markdown source (with planted sentinels) + its ordered component slots — the accumulator both
/// authoring surfaces append into, and the input `Markdown._render` splits + splices.
public struct MarkdownContent: Sendable {
    var source: String = ""
    var slots: [MarkdownSlot] = []
    var allowRawHTML: Bool = false
    var linkResolver: (@Sendable (String) -> String?)?

    init() {}

    /// The first Private-Use-Area code point used for slot sentinels.
    static let sentinelBase: UInt32 = 0xE000
    /// The inclusive end of the single PUA block — author text in `sentinelBase…sentinelEnd` is sanitized,
    /// so the only PUA scalars in `source` are planted sentinels. Bounds the slot count at 6400 (U+F8FF −
    /// U+E000 + 1) — astronomically beyond any real document's embedded-component count.
    static let sentinelEnd: UInt32 = 0xF8FF

    /// The slot index a `scalar` encodes for a content with `slotCount` slots, or `nil` if it is not a
    /// planted sentinel. (Author text is PUA-sanitized, so any in-range scalar is a sentinel.)
    static func slotIndex(of scalar: Unicode.Scalar, slotCount: Int) -> Int? {
        let value = scalar.value
        guard value >= sentinelBase, value < sentinelBase + UInt32(slotCount) else { return nil }
        return Int(value - sentinelBase)
    }

    // MARK: - accumulation (used by MarkdownString + MarkdownBuilder)

    /// Append author-trusted Markdown source verbatim (sanitized of any PUA scalar so it cannot forge a
    /// sentinel). The literal segments of a `MarkdownString` and a builder's `String` fragments land here.
    mutating func appendMarkdown(_ raw: String) { source += Self.sanitizePUA(raw) }

    /// Append an UNTRUSTED string as escaped Markdown TEXT (the safe `\(text:)` default): every Markdown
    /// metacharacter is backslash-escaped so the value renders as literal text — it can inject neither
    /// Markdown structure (a link/image/emphasis) nor, after the renderer's HTML-escaping, any markup.
    mutating func appendText(_ untrusted: String) { source += Self.escapeMarkdownText(untrusted) }

    /// Append a string as a Markdown link/image DESTINATION (`\(url:)`): characters that would break the
    /// `(…)` destination syntax are neutralized. Scheme safety is the renderer's job — it routes every
    /// destination through the `.url` escape context (scheme allowlist), so `javascript:` can never reach
    /// the DOM regardless of what is planted here.
    mutating func appendURL(_ url: String) { source += Self.escapeMarkdownURL(url) }

    /// Register a component slot and plant its sentinel into the source. Beyond the 6400-slot PUA budget
    /// the slot is dropped (it would alias author text) — a documented, unreachable-in-practice ceiling.
    mutating func appendSlot(_ slot: MarkdownSlot) {
        let index = slots.count
        guard let scalar = Unicode.Scalar(Self.sentinelBase + UInt32(index)),
            Self.sentinelBase + UInt32(index) <= Self.sentinelEnd
        else {
            return
        }
        slots.append(slot)
        source.unicodeScalars.append(scalar)
    }

    /// Concatenate another content onto this one (the `@MarkdownBuilder` join primitive), REMAPPING the
    /// other's sentinels by this content's current slot count so the two slot lists merge without index
    /// collision. The other's source is appended scalar-by-scalar, rewriting each in-range sentinel.
    mutating func appendContent(_ other: MarkdownContent) {
        let offset = slots.count
        for scalar in other.source.unicodeScalars {
            if let index = Self.slotIndex(of: scalar, slotCount: other.slots.count),
                let remapped = Unicode.Scalar(Self.sentinelBase + UInt32(offset + index))
            {
                source.unicodeScalars.append(remapped)
            } else {
                source.unicodeScalars.append(scalar)
            }
        }
        slots.append(contentsOf: other.slots)
        allowRawHTML = allowRawHTML || other.allowRawHTML
        if linkResolver == nil { linkResolver = other.linkResolver }
    }

    // MARK: - sanitization helpers

    /// Replace every Private-Use-Area scalar (`sentinelBase…sentinelEnd`) with U+FFFD, so author-supplied
    /// text can never masquerade as a planted slot sentinel.
    static func sanitizePUA(_ string: String) -> String {
        guard string.unicodeScalars.contains(where: { $0.value >= sentinelBase && $0.value <= sentinelEnd })
        else {
            return string  // the overwhelming common case: no PUA scalars, no copy
        }
        var out = String.UnicodeScalarView()
        out.reserveCapacity(string.unicodeScalars.count)
        for scalar in string.unicodeScalars {
            out.append(scalar.value >= sentinelBase && scalar.value <= sentinelEnd ? "\u{FFFD}" : scalar)
        }
        return String(out)
    }

    /// Backslash-escape the CommonMark ASCII-punctuation set so an untrusted string renders as literal
    /// text; then PUA-sanitize. (`<`/`>`/`&`/`"`/`'` are additionally HTML-escaped by the renderer.)
    static func escapeMarkdownText(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count + 8)
        for character in string {
            if character.isASCII, let scalar = character.unicodeScalars.first,
                escapablePunctuation.contains(scalar.value)
            {
                out.append("\\")
            }
            out.append(character)
        }
        return sanitizePUA(out)
    }

    /// Neutralize the characters that would terminate or break a Markdown `(destination)`; then sanitize.
    static func escapeMarkdownURL(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            switch scalar {
                case " ": out += "%20"
                case "(": out += "%28"
                case ")": out += "%29"
                case "<": out += "%3C"
                case ">": out += "%3E"
                case "\"": out += "%22"
                default:
                    if scalar.value < 0x20 { out += "" } else { out.unicodeScalars.append(scalar) }
            }
        }
        return sanitizePUA(out)
    }

    /// The CommonMark backslash-escapable ASCII punctuation (`!"#$%&'()*+,-./:;<=>?@[\]^_\`{|}~`).
    private static let escapablePunctuation: Set<UInt32> = Set(
        "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".unicodeScalars.map(\.value))
}
