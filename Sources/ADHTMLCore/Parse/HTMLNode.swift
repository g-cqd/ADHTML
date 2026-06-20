// HTMLNode — a Sendable, value-type snapshot of a parsed HTML DOM subtree, the output
// of the pure-Swift WHATWG parser (HTMLTokenizer + tree construction). Distinct from
// ADHTMLCore's GENERATION DOM (`Element`/`Builder`, for building+rendering HTML): this
// is the PARSE result — an immutable tree consumers walk to extract content. Sendable
// so it can cross actor/thread boundaries.
public indirect enum HTMLNode: Sendable, Equatable {
    case element(tag: String, attributes: [String: String], children: [HTMLNode])
    case text(String)
    case comment(String)

    /// The lowercased tag name, for elements.
    public var tag: String? {
        if case .element(let tag, _, _) = self { return tag }
        return nil
    }

    /// The element's children (empty for text/comment).
    public var children: [HTMLNode] {
        if case .element(_, _, let children) = self { return children }
        return []
    }

    /// An attribute value by (lowercased) name.
    public func attribute(_ name: String) -> String? {
        if case .element(_, let attributes, _) = self { return attributes[name.lowercased()] }
        return nil
    }

    /// Concatenated text of this node and all descendants (DOM `textContent`).
    public var textContent: String {
        switch self {
            case .text(let text): return text
            case .comment: return ""
            case .element(_, _, let children): return children.map(\.textContent).joined()
        }
    }

    /// All descendant elements with the given (lowercased) tag, in document order.
    public func elements(tag: String) -> [HTMLNode] {
        var out: [HTMLNode] = []
        collectElements(tag: tag.lowercased(), into: &out)
        return out
    }

    private func collectElements(tag: String, into out: inout [HTMLNode]) {
        if case .element(let name, _, let children) = self {
            if name == tag { out.append(self) }
            for child in children { child.collectElements(tag: tag, into: &out) }
        }
    }

    /// The first descendant element matching the (lowercased) tag, or nil.
    public func firstElement(tag: String) -> HTMLNode? {
        elements(tag: tag).first
    }
}
