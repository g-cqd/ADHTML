// Element identity is a TYPE (a phantom `Tag`), never a string — so element/attribute legality is a
// compile-time property (RFC-0004 / ADR-0009). Trait protocols (e.g. `HasHref`) gate which attributes
// an element may carry: `.href` is only offered where `Tag: HasHref`, so `href` on a `<div>` does not
// compile. This file ships the minimal Tier-C element set; the full table is generated later.

/// A statically-known HTML tag. `name` is the element name; `isVoid` marks self-closing elements
/// (`<br>`, `<img>`, …) that take no children and emit no closing tag.
public protocol HTMLTag: Sendable {
    static var name: StaticString { get }
    static var isVoid: Bool { get }
}

extension HTMLTag {
    public static var isVoid: Bool { false }
}

/// Marks tags that may carry an `href` attribute (`<a>`, `<link>`, …). The `.href(_:)` modifier is
/// offered only where `Tag: HasHref` — compile-time attribute legality (ADR-0009).
public protocol HasHref: HTMLTag {}

/// The phantom tag namespace. Types are UpperCamelCase (house lint rule); the lowercase HTML element
/// *names* live in `name`, and the DSL surface is the lowercase element functions (`div`, `span`, …),
/// so callers never write these type names directly. (Tier-C subset; full list generated later.)
public enum Tags {
    public enum Div: HTMLTag { public static let name: StaticString = "div" }
    public enum Span: HTMLTag { public static let name: StaticString = "span" }
    public enum P: HTMLTag { public static let name: StaticString = "p" }
    public enum A: HasHref { public static let name: StaticString = "a" }
    public enum Br: HTMLTag {
        public static let name: StaticString = "br"
        public static let isVoid = true
    }
}
