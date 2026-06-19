// A paired or void element: a phantom `Tag`, an ordered ``AttributeStore``, and child content. Lowers
// to `<tag …attrs>children</tag>` (or `<tag …attrs>` for void tags). Attribute modifiers return a
// copy with the attribute merged; `.href` is offered only where `Tag: HasHref` (compile-time
// attribute legality, ADR-0009).

/// An HTML element parameterized by its phantom ``HTMLTag`` and child ``HTML`` content.
public struct HTMLElement<Tag: HTMLTag, Content: HTML>: HTML {
    public var attributes: AttributeStore
    public var content: Content

    public init(attributes: AttributeStore = .empty, content: Content) {
        self.attributes = attributes
        self.content = content
    }

    public static func _render(_ html: Self, into program: inout HTMLProgram) {
        program.append(.openTagStart(Tag.name))
        for entry in html.attributes.entries {
            program.append(.attribute(name: entry.name, value: entry.value, context: entry.context))
        }
        if Tag.isVoid {
            program.append(.voidTagEnd)
        } else {
            program.append(.openTagEnd)
            Content._render(html.content, into: &program)
            program.append(.closeTag(Tag.name))
        }
    }
}

extension HTMLElement {
    /// A copy of this element with `name`=`value` set (or merged, for `class`/`style`). The value is
    /// emitted in `context` (default attribute escaping); `.href` uses `.url`.
    public func attribute(_ name: String, _ value: String, context: EscapeContext = .attribute) -> Self {
        var copy = self
        copy.attributes.set(name, value, context: context)
        return copy
    }

    /// Append to the element's `class` list (space-separated).
    public func `class`(_ value: String) -> Self { attribute("class", value) }

    /// Set the element's `id`.
    public func id(_ value: String) -> Self { attribute("id", value) }
}

extension HTMLElement where Tag: HasHref {
    /// Set the element's `href`. Offered only where the tag may carry one (`<a>`, …). The value is
    /// emitted in the URL context — scheme-allowlisted (`javascript:`/`data:` rejected, ADR-0003).
    public func href(_ value: String) -> Self { attribute("href", value, context: .url) }
}

// MARK: - Element constructors (Tier-C subset)

/// A `<div>` containing `content`.
public func div<Content: HTML>(@HTMLBuilder _ content: () -> Content) -> HTMLElement<Tags.Div, Content> {
    HTMLElement(content: content())
}

/// A `<span>` containing `content`.
public func span<Content: HTML>(@HTMLBuilder _ content: () -> Content) -> HTMLElement<Tags.Span, Content> {
    HTMLElement(content: content())
}

/// A `<p>` containing `content`.
public func p<Content: HTML>(@HTMLBuilder _ content: () -> Content) -> HTMLElement<Tags.P, Content> {
    HTMLElement(content: content())
}

/// An `<a>` containing `content`. Carries `.href(_:)`.
public func a<Content: HTML>(@HTMLBuilder _ content: () -> Content) -> HTMLElement<Tags.A, Content> {
    HTMLElement(content: content())
}

/// A `<button>` containing `content`.
public func button<Content: HTML>(@HTMLBuilder _ content: () -> Content) -> HTMLElement<Tags.Button, Content> {
    HTMLElement(content: content())
}

/// A void `<br>`.
public func br() -> HTMLElement<Tags.Br, EmptyHTML> {
    HTMLElement(content: EmptyHTML())
}
