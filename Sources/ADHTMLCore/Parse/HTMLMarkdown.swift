// HTMLMarkdown — extract plain text / Markdown from a parsed `HTMLNode` tree. This replaces the JS
// crawl's regex-on-raw-HTML converters (`src/content/parse-html/text-extract.js`): with a real DOM
// the conversion is a straightforward recursive walk (and it can keep links/code inside list items,
// which the regex version dropped). `plainText()` flattens structure to paragraph breaks; `markdown()`
// preserves headings (h3-h6), links, lists, inline/block code, and emphasis. Block elements become
// blank-line-separated paragraphs; the result is whitespace-normalized (CommonMark + the few
// extensions the renderer supports). Foundation-free.

extension HTMLNode {
    /// Flatten to plain text: block elements become paragraph breaks, inline runs concatenate,
    /// entities are already decoded by the tokenizer, and whitespace is normalized.
    public func plainText() -> String {
        var out = ""
        appendPlainText(to: &out)
        return normalizePlain(out)
    }

    /// Convert to Markdown, preserving the structure `plainText()` discards. `linkResolver` rewrites
    /// each `<a href>` URL: return a new URL, the original, or nil to drop the link (keep its text).
    public func markdown(linkResolver: ((String) -> String?)? = nil) -> String {
        var out = ""
        appendMarkdown(to: &out, linkResolver)
        return normalize(out, fenceAware: true)
    }

    private func appendPlainText(to out: inout String) {
        switch self {
            case .text(let value):
                out += value
            case .comment:
                break
            case .element(let tag, _, let children):
                if stripTags.contains(tag) { return }
                // A NUL sentinel marks block boundaries; `normalizePlain` collapses inline whitespace
                // (including text-internal newlines) to single spaces and turns sentinel runs into
                // paragraph breaks — so a newline inside a paragraph becomes a space, not a line break.
                let block = blockTags.contains(tag)
                if block { out += "\u{0}" }
                for child in children { child.appendPlainText(to: &out) }
                if block { out += "\u{0}" }
        }
    }

    private func appendMarkdown(to out: inout String, _ linkResolver: ((String) -> String?)?) {
        switch self {
            case .text(let value):
                out += value
            case .comment:
                break
            case .element(let tag, let attributes, let children):
                if stripTags.contains(tag) { return }
                switch tag {
                    case "br":
                        out += "\n"
                    case "hr":
                        out += "\n\n---\n\n"
                    case "h1", "h2", "h3", "h4", "h5", "h6":
                        let level = Int(tag.dropFirst()) ?? 1
                        let text = inlineText(children)
                        if !text.isEmpty { out += "\n\n" + String(repeating: "#", count: level) + " " + text + "\n\n" }
                    case "pre":
                        out += "\n\n```\n" + trimNewlines(rawText(children)) + "\n```\n\n"
                    case "code":
                        let text = inlineText(children)
                        if !text.isEmpty { out += "`" + String(text.map { $0 == "`" ? "'" : $0 }) + "`" }
                    case "a":
                        let text = inlineText(children)
                        if text.isEmpty { return }
                        guard let href = attributes["href"] else {
                            out += text  // named anchor / no href → keep the text
                            return
                        }
                        if let resolver = linkResolver {
                            if let resolved = resolver(href) { out += "[\(text)](\(resolved))" } else { out += text }
                        } else {
                            out += "[\(text)](\(href))"
                        }
                    case "strong", "b":
                        let text = inlineText(children)
                        if !text.isEmpty { out += "**\(text)**" }
                    case "em", "i":
                        let text = inlineText(children)
                        if !text.isEmpty { out += "*\(text)*" }
                    case "ul":
                        out += "\n\n" + listMarkdown(children, ordered: false, linkResolver) + "\n\n"
                    case "ol":
                        out += "\n\n" + listMarkdown(children, ordered: true, linkResolver) + "\n\n"
                    case "img":
                        if let src = attributes["src"] { out += "![\(attributes["alt"] ?? "")](\(src))" }
                    case "blockquote":
                        var inner = ""
                        for child in children { child.appendMarkdown(to: &inner, linkResolver) }
                        out += "\n\n" + quote(normalize(inner, fenceAware: true)) + "\n\n"
                    default:
                        let block = blockTags.contains(tag)
                        if block { out += "\n\n" }
                        for child in children { child.appendMarkdown(to: &out, linkResolver) }
                        if block { out += "\n\n" }
                }
        }
    }

    /// Inline text of a run of nodes: concatenated text content, whitespace collapsed to single spaces.
    private func inlineText(_ nodes: [HTMLNode]) -> String {
        var s = ""
        for node in nodes { s += node.textContent }
        return collapseInline(s)
    }

    /// Raw concatenated text content (no whitespace collapsing — for code blocks).
    private func rawText(_ nodes: [HTMLNode]) -> String {
        var s = ""
        for node in nodes { s += node.textContent }
        return s
    }

    /// Render `<li>` children to a one-line-per-item Markdown list (links/code/emphasis preserved).
    private func listMarkdown(_ children: [HTMLNode], ordered: Bool, _ linkResolver: ((String) -> String?)?)
        -> String
    {
        var items: [String] = []
        var index = 1
        for child in children where child.tag == "li" {
            var item = ""
            for node in child.children { node.appendMarkdown(to: &item, linkResolver) }
            let line = collapseInline(item)
            if line.isEmpty { continue }
            items.append((ordered ? "\(index). " : "- ") + line)
            index += 1
        }
        return items.joined(separator: "\n")
    }
}

extension Array where Element == HTMLNode {
    /// Plain text of a forest (the document's top-level nodes).
    public func plainText() -> String {
        var out = ""
        for node in self { out += node.plainText() + "\n\n" }
        return normalizeJoined(out)
    }
    /// Markdown of a forest.
    public func markdown(linkResolver: ((String) -> String?)? = nil) -> String {
        var out = ""
        for node in self { out += node.markdown(linkResolver: linkResolver) + "\n\n" }
        return normalizeJoined(out)
    }
}

// MARK: - Tag sets (mirror src/content/parse-html/constants.js)

private let blockTags: Set<String> = [
    "p", "div", "br", "h1", "h2", "h3", "h4", "h5", "h6", "li", "tr", "blockquote", "pre", "section",
    "article", "header", "footer", "nav", "aside", "main", "figure", "figcaption", "details", "summary",
    "ul", "ol", "dl", "dt", "dd", "table", "thead", "tbody", "tfoot"
]

/// Elements stripped entirely (chrome / non-content), including their subtree.
private let stripTags: Set<String> = ["nav", "header", "footer", "script", "style", "noscript"]

// MARK: - Whitespace normalization (Foundation-free)

/// Collapse runs of spaces/tabs to one, trim each line, and collapse 2+ blank lines to one. When
/// `fenceAware`, lines inside ```` ``` ```` fences are preserved verbatim (code indentation intact).
private func normalize(_ s: String, fenceAware: Bool) -> String {
    var out: [String] = []
    var blankRun = 0
    var inFence = false
    for rawLine in s.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        if fenceAware, trim(line) == "```" {
            if !out.isEmpty, blankRun > 0 { out.append("") }
            out.append("```")
            blankRun = 0
            inFence.toggle()
            continue
        }
        if inFence {
            out.append(line)  // verbatim
            blankRun = 0
            continue
        }
        let collapsed = collapseSpaces(line)
        if collapsed.isEmpty {
            blankRun += 1
        } else {
            if !out.isEmpty, blankRun > 0 { out.append("") }
            out.append(collapsed)
            blankRun = 0
        }
    }
    return out.joined(separator: "\n")
}

/// Normalize the already-converted pieces joined in `plainText()`/`markdown()` forest helpers.
private func normalizeJoined(_ s: String) -> String { normalize(s, fenceAware: true) }

/// Plain-text normalization: collapse ALL whitespace (incl. newlines) to single spaces, then turn
/// NUL block-boundary sentinels into paragraph breaks (so inline newlines become spaces, and only
/// block boundaries break lines).
private func normalizePlain(_ s: String) -> String {
    var collapsed = ""
    var lastSpace = false
    for ch in s {
        if ch == "\u{0}" {
            collapsed.append(ch)
            lastSpace = false
        } else if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "\u{0C}" {
            if !lastSpace { collapsed.append(" ") }
            lastSpace = true
        } else {
            collapsed.append(ch)
            lastSpace = false
        }
    }
    return collapsed.split(separator: "\u{0}").map { trim(String($0)) }.filter { !$0.isEmpty }
        .joined(separator: "\n\n")
}

/// Collapse all whitespace (incl. newlines) to single spaces, trimmed — for inline contexts.
private func collapseInline(_ s: String) -> String {
    var result = ""
    var lastSpace = true  // leading-trim: treat start as if preceded by space
    for ch in s {
        if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "\u{0C}" {
            if !lastSpace { result.append(" ") }
            lastSpace = true
        } else {
            result.append(ch)
            lastSpace = false
        }
    }
    if result.hasSuffix(" ") { result.removeLast() }
    return result
}

/// Collapse runs of spaces/tabs to one and trim the line (newlines already split out).
private func collapseSpaces(_ line: String) -> String {
    var result = ""
    var lastSpace = true
    for ch in line {
        if ch == " " || ch == "\t" {
            if !lastSpace { result.append(" ") }
            lastSpace = true
        } else {
            result.append(ch)
            lastSpace = false
        }
    }
    if result.hasSuffix(" ") { result.removeLast() }
    return result
}

private func trim(_ s: String) -> String {
    var start = s.startIndex
    var end = s.endIndex
    while start < end, s[start] == " " || s[start] == "\t" { start = s.index(after: start) }
    while end > start {
        let prev = s.index(before: end)
        guard s[prev] == " " || s[prev] == "\t" else { break }
        end = prev
    }
    return String(s[start ..< end])
}

private func trimNewlines(_ s: String) -> String {
    var start = s.startIndex
    var end = s.endIndex
    while start < end, s[start] == "\n" || s[start] == "\r" { start = s.index(after: start) }
    while end > start {
        let prev = s.index(before: end)
        guard s[prev] == "\n" || s[prev] == "\r" else { break }
        end = prev
    }
    return String(s[start ..< end])
}

private func quote(_ s: String) -> String {
    s.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.isEmpty ? ">" : "> " + $0 }
        .joined(separator: "\n")
}
