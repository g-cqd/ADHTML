// The template-literal authoring surface: `Markdown("# \(title)\n\nBuy: \(BuyButton(sku))")`. A
// `MarkdownString` is `ExpressibleByStringInterpolation`, so the literal segments are author-trusted
// Markdown and the interpolations are typed:
//   • `\(component)` / `\(optional)` — embed a live `some HTML` as a slot (no slot when the optional is nil)
//   • `\(text:)` — an untrusted string as ESCAPED Markdown text (the safe default)
//   • `\(url:)`  — a sanitized link/image destination
// There is deliberately NO `appendInterpolation(_: String)` overload: a bare `\(someString)` then fails to
// compile (a `String` is not `HTML`), closing the injection footgun — untrusted strings must go through
// `\(text:)`.
public import protocol ADHTMLCore.HTML

/// A Markdown literal with typed interpolations — the value `Markdown(_:)` consumes.
public struct MarkdownString: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    var content: MarkdownContent

    public init(stringLiteral value: String) {
        var content = MarkdownContent()
        content.appendMarkdown(value)
        self.content = content
    }

    public init(stringInterpolation: StringInterpolation) {
        self.content = stringInterpolation.content
    }

    /// Accumulates literal Markdown + typed interpolations into a ``MarkdownContent``.
    public struct StringInterpolation: StringInterpolationProtocol {
        var content = MarkdownContent()

        public init(literalCapacity: Int, interpolationCount: Int) {}

        /// A literal segment — author-trusted Markdown.
        public mutating func appendLiteral(_ literal: String) { content.appendMarkdown(literal) }

        /// `\(component)` — embed a live component as a slot (rendered with full hydration fidelity).
        public mutating func appendInterpolation(_ component: some HTML) {
            content.appendSlot(MarkdownSlot(component))
        }

        /// `\(optional)` — embed a component when non-nil; plant nothing when nil (no empty slot).
        public mutating func appendInterpolation(_ component: (some HTML)?) {
            if let component { content.appendSlot(MarkdownSlot(component)) }
        }

        /// `\(text:)` — an untrusted string as escaped Markdown text (the safe default).
        public mutating func appendInterpolation(text: String) { content.appendText(text) }

        /// `\(url:)` — a sanitized link/image destination.
        public mutating func appendInterpolation(url: String) { content.appendURL(url) }
    }
}
