// Leaf content nodes. `Text` is escaped by default in the text context at emit time; `RawHTML` is the
// single, conspicuously-named, greppable bypass (ADR-0003) — grep `RawHTML` to enumerate every
// unescaped insertion in review.

/// Escaped text content. A bare `String` in an ``HTMLBuilder`` block becomes a `Text` automatically.
public struct Text: HTML {
    public let value: String
    public init(_ value: String) { self.value = value }
    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        target.text(html.value)
    }
}

/// Pre-escaped, trusted markup emitted verbatim. **The only unescaped path in the engine.** The
/// caller asserts the bytes are already safe HTML; misuse is an XSS vector, so it is named to be
/// greppable and is excluded from no audit.
public struct RawHTML: HTML {
    public let bytes: [UInt8]
    /// Emit `html`'s UTF-8 verbatim. The caller guarantees it is already safe.
    public init(unsafelyEscaped html: String) { self.bytes = Array(html.utf8) }
    /// Emit `bytes` verbatim. The caller guarantees they are already safe.
    public init(unsafelyEscaped bytes: [UInt8]) { self.bytes = bytes }
    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        target.raw(html.bytes)
    }
}
