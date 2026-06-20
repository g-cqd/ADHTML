// Element identity is a TYPE (a phantom `Tag`), never a string — so element/attribute legality is a
// compile-time property (RFC-0004 / ADR-0009). The trait protocols that gate element-specific attributes
// live in Traits.swift; the full `Tags` namespace and the lowercase element constructors are generated
// (DOM/Generated, by ADHTMLCodegen).

/// A statically-known HTML tag. The open/close markup is precomputed (`"<div"` / `"</div>"`) so an
/// element emits two `writeStatic`s instead of assembling `<`/name/`>` byte by byte — a measured render
/// hot-path win. `isVoid` marks self-closing elements (`<br>`, `<img>`, …) that take no children and
/// emit no closing tag (their `closeMarkup` is unused).
public protocol HTMLTag: Sendable {
    /// The open-tag prefix, without the closing `>`: `"<div"`. Attributes and `>` follow.
    static var openMarkup: StaticString { get }
    /// The full closing tag: `"</div>"`.
    static var closeMarkup: StaticString { get }
    static var isVoid: Bool { get }
}

extension HTMLTag {
    public static var isVoid: Bool { false }
}
