internal import Markdown

// ADHTMLMarkdown (gated `ADHTML_MARKDOWN`) — the Markdown → HTML renderer ADHTML owns. swift-markdown
// (cmark-gfm) parses to an AST; this walks that AST with a `MarkupVisitor` whose `Result == String` and
// emits ESCAPED HTML, routing every text / attribute / URL value through ADHTMLCore's context-aware
// `Escaper`. That escape-by-default posture is the whole point of owning the renderer: swift-markdown's
// bundled `HTMLFormatter` interpolates node text VERBATIM (an XSS hole for untrusted Markdown), whereas
// this one cannot under-escape. GFM tables + strikethrough + task-lists are cmark-gfm defaults, so the
// plain `Document(parsing:)` already yields them — no extra `ParseOptions`.
//
// Kept behind `ADHTML_MARKDOWN` because swift-markdown is a C (cmark-gfm) dependency (ADR-0010/0011); the
// default product graph never resolves it, and only this gated target imports `Markdown`.
//
// ADHTMLCore is imported SELECTIVELY (just the escaper surface): both modules define `Text`, `Table`,
// `Image`, … (ADHTMLCore's HTML DOM vs swift-markdown's AST), so pulling the whole core in would make
// every node type ambiguous. Selective imports leave every bare type name resolving to `Markdown`.
internal import struct ADHTMLCore.ArraySink
internal import enum ADHTMLCore.EscapeContext
internal import enum ADHTMLCore.Escaper

/// The Markdown → HTML renderer (ADHTML owns the HTML; swift-markdown only supplies the AST).
public enum ADHTMLMarkdown {
    /// Render `markdown` (CommonMark + the GFM tables / strikethrough / task-list extensions) to an
    /// escaped HTML fragment (no surrounding document).
    ///
    /// - Parameters:
    ///   - markdown: the source text.
    ///   - linkResolver: an optional rewrite for link + image destinations (e.g. corpus-internal links →
    ///     site paths). It returns the resolved URL, or `nil` to keep the original. The result is STILL
    ///     scheme-allowlisted + escaped (the `.url` context), so a resolver can never inject a dangerous
    ///     URL such as `javascript:`.
    ///   - allowRawHTML: when `false` (the default), raw HTML blocks + inline spans are emitted ESCAPED —
    ///     shown as literal text, never passed through — closing Markdown's one injection vector. Set it
    ///     `true` only for fully-trusted input.
    /// - Returns: an escaped HTML fragment (no surrounding `<html>` / `<body>`).
    public static func render(
        _ markdown: String, linkResolver: ((String) -> String?)? = nil, allowRawHTML: Bool = false
    ) -> String {
        var renderer = Renderer(linkResolver: linkResolver, allowRawHTML: allowRawHTML)
        return renderer.visit(Document(parsing: markdown))
    }
}

/// A `MarkupVisitor` that renders each node to its escaped-HTML string: container nodes wrap their
/// children's rendered output, leaf text is escaped through ADHTMLCore's `Escaper`. Table rendering
/// state (column alignments / head-vs-body / current column) is threaded as visitor state, mirroring
/// swift-markdown's `HTMLFormatter` — but here every emitted value is escaped.
private struct Renderer: MarkupVisitor {
    typealias Result = String

    let linkResolver: ((String) -> String?)?
    let allowRawHTML: Bool

    // Table state: set on entering a `Table`, read by its cells.
    var tableColumnAlignments: [Table.ColumnAlignment?]?
    var inTableHead = false
    var currentTableColumn = 0

    // MARK: - descend + the safe default

    /// Render every child of `markup` and concatenate — the descend primitive for container nodes.
    mutating func renderChildren(_ markup: any Markup) -> String {
        var out = ""
        for child in markup.children { out += visit(child) }
        return out
    }

    /// Any node we don't special-case renders its children (a safe passthrough — never raw text).
    mutating func defaultVisit(_ markup: any Markup) -> String { renderChildren(markup) }

    // MARK: - block elements

    mutating func visitDocument(_ document: Document) -> String { renderChildren(document) }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = Swift.min(Swift.max(heading.level, 1), 6)
        return "<h\(level)>\(renderChildren(heading))</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(renderChildren(paragraph))</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n\(renderChildren(blockQuote))</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let languageAttr =
            codeBlock.language.map { " class=\"language-\(escape($0, .attribute))\"" } ?? ""
        return "<pre><code\(languageAttr)>\(escape(codeBlock.code, .text))</code></pre>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        "<ul>\n\(renderChildren(unorderedList))</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        // CommonMark's default start is 1 → omit the `start` attribute (mirrors HTMLFormatter).
        let startAttr = orderedList.startIndex != 1 ? " start=\"\(orderedList.startIndex)\"" : ""
        return "<ol\(startAttr)>\n\(renderChildren(orderedList))</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        var out = "<li>"
        if let checkbox = listItem.checkbox {
            out += "<input type=\"checkbox\" disabled=\"\""
            if checkbox == .checked { out += " checked=\"\"" }
            out += " /> "
        }
        out += renderChildren(listItem)
        out += "</li>\n"
        return out
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String { "<hr />\n" }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        allowRawHTML ? html.rawHTML : escape(html.rawHTML, .text)
    }

    // MARK: - inline elements

    mutating func visitText(_ text: Text) -> String { escape(text.string, .text) }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(renderChildren(emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(renderChildren(strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(renderChildren(strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escape(inlineCode.code, .text))</code>"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        allowRawHTML ? inlineHTML.rawHTML : escape(inlineHTML.rawHTML, .text)
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br />\n" }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { "\n" }

    mutating func visitLink(_ link: Link) -> String {
        let hrefAttr = resolvedURL(link.destination).map { " href=\"\(escape($0, .url))\"" } ?? ""
        return "<a\(hrefAttr)>\(renderChildren(link))</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        var out = "<img"
        if let source = resolvedURL(image.source), !source.isEmpty {
            out += " src=\"\(escape(source, .url))\""
        }
        let alt = image.plainText
        if !alt.isEmpty { out += " alt=\"\(escape(alt, .attribute))\"" }
        if let title = image.title, !title.isEmpty {
            out += " title=\"\(escape(title, .attribute))\""
        }
        out += " />"
        return out
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String {
        symbolLink.destination.map { "<code>\(escape($0, .text))</code>" } ?? ""
    }

    // MARK: - tables (GFM)

    mutating func visitTable(_ table: Table) -> String {
        tableColumnAlignments = table.columnAlignments
        let body = renderChildren(table)
        tableColumnAlignments = nil
        return "<table>\n\(body)</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        inTableHead = true
        currentTableColumn = 0
        let cells = renderChildren(tableHead)
        inTableHead = false
        return "<thead>\n<tr>\n\(cells)</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        tableBody.isEmpty ? "" : "<tbody>\n\(renderChildren(tableBody))</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> String {
        currentTableColumn = 0
        return "<tr>\n\(renderChildren(tableRow))</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> String {
        guard let alignments = tableColumnAlignments, currentTableColumn < alignments.count,
            tableCell.colspan > 0, tableCell.rowspan > 0
        else { return "" }

        let element = inTableHead ? "th" : "td"
        var out = "<\(element)"
        if let alignment = alignments[currentTableColumn] {
            out += " align=\"\(Self.alignmentName(alignment))\""
        }
        currentTableColumn += 1
        if tableCell.rowspan > 1 { out += " rowspan=\"\(tableCell.rowspan)\"" }
        if tableCell.colspan > 1 { out += " colspan=\"\(tableCell.colspan)\"" }
        out += ">\(renderChildren(tableCell))</\(element)>\n"
        return out
    }

    // MARK: - helpers

    /// Apply the link resolver (if any) to a destination, falling back to the original URL.
    func resolvedURL(_ destination: String?) -> String? {
        guard let destination else { return nil }
        return linkResolver?(destination) ?? destination
    }

    /// Escape `value` for `context` through ADHTMLCore's audited encoder — the renderer's SINGLE escaping
    /// path (text, attribute, and URL all route here), so nothing reaches the output unescaped.
    func escape(_ value: String, _ context: EscapeContext) -> String {
        var sink = ArraySink(reservingCapacity: value.utf8.count)
        Escaper.write(value, context: context, into: &sink)
        return String(decoding: sink.bytes, as: UTF8.self)
    }

    /// `Table.ColumnAlignment` → the HTML `align` value (the enum has no `CustomStringConvertible`).
    static func alignmentName(_ alignment: Table.ColumnAlignment) -> String {
        switch alignment {
            case .left: return "left"
            case .center: return "center"
            case .right: return "right"
        }
    }
}
