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
    /// This element with `name`=`value` set (or merged, for `class`/`style`), emitted in `context`
    /// (default attribute escaping; `.href` uses `.url`). `consuming`: a modifier chain on a dying
    /// temporary *moves* `self`, so the attribute store is uniquely held and mutated in place — the
    /// chain pays one allocation, not one deep copy per link (CoW-tax bypass). Storing then modifying
    /// still copies, exactly as before.
    public consuming func attribute(
        _ name: String, _ value: String, context: EscapeContext = .attribute
    ) -> Self {
        var copy = consume self
        copy.attributes.set(name, value, context: context)
        return copy
    }

    /// Append to the element's `class` list (space-separated).
    public consuming func `class`(_ value: String) -> Self { attribute("class", value) }

    /// Set the element's `id`.
    public consuming func id(_ value: String) -> Self { attribute("id", value) }
}
