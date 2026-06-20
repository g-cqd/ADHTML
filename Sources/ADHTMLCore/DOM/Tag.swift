// Element identity is a TYPE (a phantom `Tag`), never a string — so element/attribute legality is a
// compile-time property (RFC-0004 / ADR-0009). The trait protocols that gate element-specific attributes
// live in Traits.swift; the full `Tags` namespace and the lowercase element constructors are generated
// (DOM/Generated, by ADHTMLCodegen).

/// A statically-known HTML tag. `name` is the element name; `isVoid` marks self-closing elements
/// (`<br>`, `<img>`, …) that take no children and emit no closing tag.
public protocol HTMLTag: Sendable {
    static var name: StaticString { get }
    static var isVoid: Bool { get }
}

extension HTMLTag {
    public static var isVoid: Bool { false }
}
