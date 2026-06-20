// HTMLExtract — structured content extraction from a parsed page: title, description, and the body
// split into heading/content sections. The native port of the JS crawl's `extractHtmlContent`
// (src/content/parse-html.js): locate the content container (an explicit selector, else
// main/article/.content/#content, else body), drop chrome, take the title (meta or first h1), and
// split the body at h2 (h3 fallback) into sections rendered as Markdown or plain text. Also exposes
// the small element-query surface (simple `tag` / `.class` / `#id` selectors, attribute reads) the
// extractor and the crawl adapters need. Generic + reusable; the crawl-specific NormalizedPage
// mapping lives in ADBuilder.

// MARK: - Element queries

extension HTMLNode {
    /// The element's `id` attribute, if any.
    public var elementID: String? { attribute("id") }

    /// The element's space-separated `class` tokens.
    public var classList: [String] {
        guard let value = attribute("class") else { return [] }
        return value.split { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }.map(String.init)
    }

    /// First node (self or descendant, document order) satisfying `predicate`.
    public func first(where predicate: (HTMLNode) -> Bool) -> HTMLNode? {
        if predicate(self) { return self }
        for child in children {
            if let found = child.first(where: predicate) { return found }
        }
        return nil
    }

    /// First descendant element matching a simple selector: `tag`, `.class`, or `#id`.
    public func firstElement(matching selector: String) -> HTMLNode? {
        if let className = selector.dropPrefix(".") {
            return first { $0.classList.contains(className) }
        }
        if let identifier = selector.dropPrefix("#") {
            return first { $0.elementID == identifier }
        }
        return firstElement(tag: selector)
    }
}

extension [HTMLNode] {
    /// All descendant elements (across the forest) with the given lowercased tag, in document order.
    public func elements(tag: String) -> [HTMLNode] { flatMap { $0.elements(tag: tag) } }

    /// First element across the forest matching a simple `tag` / `.class` / `#id` selector.
    public func firstElement(matching selector: String) -> HTMLNode? {
        for node in self {
            if let found = node.firstElement(matching: selector) { return found }
        }
        return nil
    }
}

private extension String {
    /// The remainder after `prefix`, or nil if `self` doesn't start with it.
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

// MARK: - Extracted content

/// One heading/content section of an extracted page.
public struct HTMLSection: Sendable, Equatable {
    public let heading: String?
    public let content: String
    public init(heading: String?, content: String) {
        self.heading = heading
        self.content = content
    }
}

/// The structured result of `HTMLDocument.extract`.
public struct HTMLExtractedContent: Sendable, Equatable {
    public let title: String?
    public let description: String?
    public let sections: [HTMLSection]
    public init(title: String?, description: String?, sections: [HTMLSection]) {
        self.title = title
        self.description = description
        self.sections = sections
    }
}

/// Page-level extraction entry points.
public enum HTMLDocument {
    /// Extract `{ title, description, sections }` from an HTML page.
    ///
    /// - Parameters:
    ///   - html: the page source.
    ///   - containerSelector: an explicit content-container selector (`tag` / `.class` / `#id`); when
    ///     nil, falls back to `main`, `article`, `.content`, `#content`, `#contents`, then `body`.
    ///   - preserveStructure: render section bodies as Markdown (true) or plain text (false).
    ///   - linkResolver: rewrites each `<a href>` when rendering Markdown (see `HTMLNode.markdown`).
    public static func extract(
        _ html: String, containerSelector: String? = nil, preserveStructure: Bool = false,
        linkResolver: ((String) -> String?)? = nil
    ) -> HTMLExtractedContent {
        let roots = HTMLNode.parse(html)

        let title = metaContent(roots, property: "og:title")
            ?? roots.firstElement(matching: "title").map { $0.plainText() }.flatMap { $0.isEmpty ? nil : $0 }
            ?? roots.firstElement(matching: "h1").map { $0.plainText() }.flatMap { $0.isEmpty ? nil : $0 }
        let description = metaContent(roots, name: "description")
            ?? metaContent(roots, property: "og:description")

        var container = containerSelector.flatMap { roots.firstElement(matching: $0) }
        if container == nil {
            for selector in ["main", "article", ".content", "#content", "#contents"] {
                if let found = roots.firstElement(matching: selector) {
                    container = found
                    break
                }
            }
        }
        let body =
            container?.children
            ?? roots.firstElement(matching: "body")?.children
            ?? roots

        let sections = splitSections(body, preserveStructure: preserveStructure, linkResolver: linkResolver)
        return HTMLExtractedContent(title: title, description: description, sections: sections)
    }
}

// MARK: - Internals

/// A `<meta name=… content=…>` value.
private func metaContent(_ roots: [HTMLNode], name: String) -> String? {
    meta(roots) { $0.attribute("name") == name }
}
/// A `<meta property=… content=…>` value (Open Graph).
private func metaContent(_ roots: [HTMLNode], property: String) -> String? {
    meta(roots) { $0.attribute("property") == property }
}
private func meta(_ roots: [HTMLNode], _ match: (HTMLNode) -> Bool) -> String? {
    for element in roots.elements(tag: "meta") where match(element) {
        if let content = element.attribute("content"), !content.isEmpty { return content }
    }
    return nil
}

/// Split a body (the content container's children) at h2 (h3 fallback) into sections.
private func splitSections(
    _ body: [HTMLNode], preserveStructure: Bool, linkResolver: ((String) -> String?)?
) -> [HTMLSection] {
    let splitTag = body.elements(tag: "h2").isEmpty ? "h3" : "h2"

    func render(_ nodes: [HTMLNode]) -> String {
        preserveStructure ? nodes.markdown(linkResolver: linkResolver) : nodes.plainText()
    }

    var sections: [HTMLSection] = []
    var heading: String?
    var nodes: [HTMLNode] = []

    func flush() {
        let content = render(nodes)
        if heading != nil || !content.isEmpty {
            sections.append(HTMLSection(heading: heading, content: content))
        }
        nodes = []
    }

    for node in body {
        if node.tag == splitTag {
            flush()
            let text = node.plainText()
            heading = text.isEmpty ? nil : text
        } else {
            nodes.append(node)
        }
    }
    flush()

    if sections.isEmpty {
        sections.append(HTMLSection(heading: nil, content: render(body)))
    }
    return sections
}
