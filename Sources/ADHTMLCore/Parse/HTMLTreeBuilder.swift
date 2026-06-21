// HTMLTreeBuilder — the tree-construction stage: fold the tokenizer's flat token stream (walked
// straight off `HTMLTape`) into the nested `HTMLNode` DOM. This is a PRAGMATIC subset of the WHATWG
// tree-construction algorithm — enough for the real, mostly-well-formed documentation HTML the crawl
// extracts from (DocC output, HIG/guideline pages), not the full insertion-mode state machine with
// the adoption-agency algorithm. It covers: void elements (no children, even without `/>`), implied
// end tags (`<li>`, `<p>`, list/table/select items that omit their close tag), nearest-match end-tag
// closing (a stray end tag is ignored; an end tag mid-stack closes the intervening open elements),
// and adjacent-text coalescing. Attributes collapse to a dictionary, first occurrence winning (the
// WHATWG duplicate-attribute rule).

extension HTMLTape {
    /// Build the parsed DOM forest (top-level nodes) from the tape.
    public func tree() -> [HTMLNode] {
        var builder = TreeBuilder()
        var i = 0
        while i < slotCount {
            let (token, next) = decoded(at: i)
            builder.consume(token)
            i = next
        }
        return builder.finish()
    }
}

extension HTMLNode {
    /// Parse `html` into a DOM forest (tokenize + tree-construct).
    public static func parse(_ html: String) -> [HTMLNode] { HTMLTape.build(html).tree() }
}

/// The open-element stack + completed roots. Each frame accumulates its children until it is closed.
private struct TreeBuilder {
    private struct Frame {
        let tag: String
        let attributes: [String: String]
        var children: [HTMLNode]
    }

    private var stack: [Frame] = []
    private var roots: [HTMLNode] = []

    /// Maximum element-nesting depth: beyond it a start tag is coerced to a childless LEAF instead of
    /// opening a new frame, so the built tree can never be deeper than this. The tokenizer + this builder
    /// are iterative (they would fold `<div>`×100000 into a 100000-deep tree), but the crawl feeds UNTRUSTED
    /// HTML (DocC/HIG pages) and the downstream `markdown()`/`plainText()`/`first(where:)` passes walk the
    /// tree by RECURSION — so the bound is sized for THEM: well under a worst-case ~512 KiB worker-thread
    /// stack (the renderer's iterative 512 ceiling would still let those recursive walks overflow), yet far
    /// deeper than real documentation HTML ever nests (a handful of levels). An adversarial deeply-nested
    /// page is thus flattened, never a stack overflow (failure-safe, ADR-0002).
    private static let maxDepth = 128

    mutating func consume(_ token: HTMLToken) {
        switch token {
            case .startTag(let name, let attributes, let selfClosing):
                impliedClose(before: name)
                let attrs = dictionary(attributes)
                if selfClosing || voidElements.contains(name) || stack.count >= Self.maxDepth {
                    append(.element(tag: name, attributes: attrs, children: []))
                } else {
                    stack.append(Frame(tag: name, attributes: attrs, children: []))
                }
            case .endTag(let name):
                close(name)
            case .text(let value):
                appendText(value)
            case .comment(let value):
                append(.comment(value))
            case .doctype:
                break  // DOCTYPE carries no DOM node
        }
    }

    /// Close any still-open elements at end of input, outermost last, and return the roots.
    mutating func finish() -> [HTMLNode] {
        while !stack.isEmpty { popFrame() }
        return roots
    }

    // MARK: - stack operations

    /// Append a finished node to the current open element (or to the roots if none is open).
    private mutating func append(_ node: HTMLNode) {
        if stack.isEmpty {
            roots.append(node)
        } else {
            stack[stack.count - 1].children.append(node)
        }
    }

    /// Append text, coalescing with an immediately preceding text sibling.
    private mutating func appendText(_ value: String) {
        if value.isEmpty { return }
        if stack.isEmpty {
            if case .text(let prev) = roots.last {
                roots[roots.count - 1] = .text(prev + value)
            } else {
                roots.append(.text(value))
            }
        } else {
            let top = stack.count - 1
            if case .text(let prev) = stack[top].children.last {
                stack[top].children[stack[top].children.count - 1] = .text(prev + value)
            } else {
                stack[top].children.append(.text(value))
            }
        }
    }

    /// Pop the innermost frame and nest it into its parent (or the roots).
    private mutating func popFrame() {
        let frame = stack.removeLast()
        append(.element(tag: frame.tag, attributes: frame.attributes, children: frame.children))
    }

    /// Close to the nearest open element named `name`, nesting the closed elements into their parents.
    /// A stray end tag with no matching open element is ignored (WHATWG parse-error recovery).
    private mutating func close(_ name: String) {
        var index = stack.count - 1
        while index >= 0, stack[index].tag != name { index -= 1 }
        guard index >= 0 else { return }
        while stack.count > index { popFrame() }
    }

    /// Auto-close elements whose end tag is commonly omitted, before opening `name`. Each rule closes
    /// to the nearest matching open element, but only within a scope barrier — so a nested `<ul>`'s
    /// `<li>` does not close the outer `<li>`, and a `<td>` does not close a cell in a prior row.
    private mutating func impliedClose(before name: String) {
        switch name {
            case "li":
                closeToNearest(["li"], barrier: ["ul", "ol", "menu"])
            case "dt", "dd":
                closeToNearest(["dt", "dd"], barrier: ["dl"])
            case "option":
                closeToNearest(["option"], barrier: ["select", "datalist", "optgroup"])
            case "optgroup":
                closeToNearest(["optgroup", "option"], barrier: ["select"])
            case "tr":
                closeToNearest(["tr"], barrier: ["table"])
            case "td", "th":
                closeToNearest(["td", "th"], barrier: ["tr", "table"])
            case "thead", "tbody", "tfoot":
                closeToNearest(["thead", "tbody", "tfoot"], barrier: ["table"])
            default:
                if blockElements.contains(name) { closeToNearest(["p"], barrier: []) }
        }
    }

    /// Pop to the nearest open element whose tag is in `targets`, stopping with no change if a
    /// `barrier` tag is reached first (an approximation of WHATWG element scopes).
    private mutating func closeToNearest(_ targets: Set<String>, barrier: Set<String>) {
        var index = stack.count - 1
        while index >= 0 {
            let tag = stack[index].tag
            if targets.contains(tag) {
                while stack.count > index { popFrame() }
                return
            }
            if barrier.contains(tag) { return }
            index -= 1
        }
    }

    /// Ordered attributes -> dictionary, first occurrence winning (WHATWG duplicate-attribute rule).
    private func dictionary(_ attributes: [HTMLAttribute]) -> [String: String] {
        guard !attributes.isEmpty else { return [:] }
        var dict = [String: String](minimumCapacity: attributes.count)
        for attribute in attributes where dict[attribute.name] == nil {
            dict[attribute.name] = attribute.value
        }
        return dict
    }
}

/// Elements that never have children (and so never push onto the open-element stack).
private let voidElements: Set<String> = [
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source",
    "track", "wbr"
]

/// Block-level elements whose start tag implicitly closes an open `<p>`.
private let blockElements: Set<String> = [
    "address", "article", "aside", "blockquote", "details", "div", "dl", "fieldset", "figcaption",
    "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "main",
    "menu", "nav", "ol", "p", "pre", "section", "table", "ul"
]
