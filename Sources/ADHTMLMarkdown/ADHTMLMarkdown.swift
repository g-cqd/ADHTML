internal import Markdown

// ADHTMLMarkdown (gated `ADHTML_MARKDOWN`) — the Markdown → HTML renderer ADHTML owns. swift-markdown
// (cmark-gfm) parses to an AST; this walks that AST with a `MarkupVisitor` whose `Result == Void`,
// appending ESCAPED HTML into ONE shared byte accumulator (`ArraySink`) threaded through the walk, and
// routing every text / attribute / URL value through ADHTMLCore's context-aware `Escaper`. The single
// accumulator makes the walk O(N): each node appends into the shared buffer instead of returning a fresh
// `String` its ancestors re-copy, and `escape` writes escaped bytes straight into the buffer (no
// per-leaf bytes→String round-trip). That escape-by-default posture is the whole point of owning the
// renderer: swift-markdown's bundled `HTMLFormatter` interpolates node text VERBATIM (an XSS hole for
// untrusted Markdown), whereas this one cannot under-escape. GFM tables + strikethrough + task-lists are
// cmark-gfm defaults, so the plain `Document(parsing:)` already yields them — no extra `ParseOptions`.
//
// Kept behind `ADHTML_MARKDOWN` because swift-markdown is a C (cmark-gfm) dependency (ADR-0010/0011); the
// default product graph never resolves it, and only this gated target imports `Markdown`.
//
// ADHTMLCore is imported SELECTIVELY (just the escaper + sink surface): both modules define `Text`,
// `Table`, `Image`, … (ADHTMLCore's HTML DOM vs swift-markdown's AST), so pulling the whole core in would
// make every node type ambiguous. Selective imports leave every bare type name resolving to `Markdown`.
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
        var renderer = Renderer(
            linkResolver: linkResolver, allowRawHTML: allowRawHTML,
            reservingCapacity: markdown.utf8.count)
        renderer.visit(Document(parsing: markdown))
        return String(decoding: renderer.out.bytes, as: UTF8.self)
    }
}

/// A `MarkupVisitor` that appends each node's escaped HTML into ONE shared `ArraySink`: container nodes
/// emit their open tag, descend (their children append in place), then emit their close tag; leaf text is
/// escaped straight into the buffer. Nothing returns an intermediate `String`, so the walk is O(N) with
/// no per-subtree re-copy. Table rendering state (column alignments / head-vs-body / current column) is
/// threaded as visitor state, mirroring swift-markdown's `HTMLFormatter` — but here every emitted value
/// is escaped.
private struct Renderer: MarkupVisitor {
    typealias Result = Void

    let linkResolver: ((String) -> String?)?
    let allowRawHTML: Bool

    /// The single shared output accumulator: every node appends here, in document order.
    var out: ArraySink

    // Table state: set on entering a `Table`, read by its cells.
    var tableColumnAlignments: [Table.ColumnAlignment?]?
    var inTableHead = false
    var currentTableColumn = 0

    init(linkResolver: ((String) -> String?)?, allowRawHTML: Bool, reservingCapacity: Int) {
        self.linkResolver = linkResolver
        self.allowRawHTML = allowRawHTML
        out = ArraySink(reservingCapacity: reservingCapacity)
    }

    // MARK: - descend + the safe default

    /// Descend into every child of `markup` (each appends into the shared `out`) — the primitive for
    /// container nodes.
    mutating func renderChildren(_ markup: any Markup) {
        for child in markup.children { visit(child) }
    }

    /// Any node we don't special-case renders its children (a safe passthrough — never raw text).
    mutating func defaultVisit(_ markup: any Markup) { renderChildren(markup) }

    // MARK: - block elements

    mutating func visitDocument(_ document: Document) { renderChildren(document) }

    mutating func visitHeading(_ heading: Heading) {
        let level = Swift.min(Swift.max(heading.level, 1), 6)
        out.emitDynamic("<h\(level)>")
        renderChildren(heading)
        out.emitDynamic("</h\(level)>\n")
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        out.emit("<p>")
        renderChildren(paragraph)
        out.emit("</p>\n")
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        out.emit("<blockquote>\n")
        renderChildren(blockQuote)
        out.emit("</blockquote>\n")
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        out.emit("<pre><code")
        if let language = codeBlock.language {
            out.emit(" class=\"language-")
            escape(language, .attribute)
            out.emit("\"")
        }
        out.emit(">")
        escape(codeBlock.code, .text)
        out.emit("</code></pre>\n")
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        out.emit("<ul>\n")
        renderChildren(unorderedList)
        out.emit("</ul>\n")
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        out.emit("<ol")
        // CommonMark's default start is 1 → omit the `start` attribute (mirrors HTMLFormatter).
        if orderedList.startIndex != 1 { out.emitDynamic(" start=\"\(orderedList.startIndex)\"") }
        out.emit(">\n")
        renderChildren(orderedList)
        out.emit("</ol>\n")
    }

    mutating func visitListItem(_ listItem: ListItem) {
        out.emit("<li>")
        if let checkbox = listItem.checkbox {
            out.emit("<input type=\"checkbox\" disabled=\"\"")
            if checkbox == .checked { out.emit(" checked=\"\"") }
            out.emit(" /> ")
        }
        renderChildren(listItem)
        out.emit("</li>\n")
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) { out.emit("<hr />\n") }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        if allowRawHTML { out.emitDynamic(html.rawHTML) } else { escape(html.rawHTML, .text) }
    }

    // MARK: - inline elements

    mutating func visitText(_ text: Text) { escape(text.string, .text) }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        out.emit("<em>")
        renderChildren(emphasis)
        out.emit("</em>")
    }

    mutating func visitStrong(_ strong: Strong) {
        out.emit("<strong>")
        renderChildren(strong)
        out.emit("</strong>")
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        out.emit("<del>")
        renderChildren(strikethrough)
        out.emit("</del>")
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        out.emit("<code>")
        escape(inlineCode.code, .text)
        out.emit("</code>")
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        if allowRawHTML { out.emitDynamic(inlineHTML.rawHTML) } else { escape(inlineHTML.rawHTML, .text) }
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) { out.emit("<br />\n") }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) { out.emit("\n") }

    mutating func visitLink(_ link: Link) {
        out.emit("<a")
        if let href = resolvedURL(link.destination) {
            out.emit(" href=\"")
            escape(href, .url)
            out.emit("\"")
        }
        out.emit(">")
        renderChildren(link)
        out.emit("</a>")
    }

    mutating func visitImage(_ image: Image) {
        out.emit("<img")
        if let source = resolvedURL(image.source), !source.isEmpty {
            out.emit(" src=\"")
            escape(source, .url)
            out.emit("\"")
        }
        let alt = image.plainText
        if !alt.isEmpty {
            out.emit(" alt=\"")
            escape(alt, .attribute)
            out.emit("\"")
        }
        if let title = image.title, !title.isEmpty {
            out.emit(" title=\"")
            escape(title, .attribute)
            out.emit("\"")
        }
        out.emit(" />")
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
        guard let destination = symbolLink.destination else { return }
        out.emit("<code>")
        escape(destination, .text)
        out.emit("</code>")
    }

    // MARK: - tables (GFM)

    mutating func visitTable(_ table: Table) {
        tableColumnAlignments = table.columnAlignments
        out.emit("<table>\n")
        renderChildren(table)
        tableColumnAlignments = nil
        out.emit("</table>\n")
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        inTableHead = true
        currentTableColumn = 0
        out.emit("<thead>\n<tr>\n")
        renderChildren(tableHead)
        inTableHead = false
        out.emit("</tr>\n</thead>\n")
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        guard !tableBody.isEmpty else { return }
        out.emit("<tbody>\n")
        renderChildren(tableBody)
        out.emit("</tbody>\n")
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        currentTableColumn = 0
        out.emit("<tr>\n")
        renderChildren(tableRow)
        out.emit("</tr>\n")
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        guard let alignments = tableColumnAlignments, currentTableColumn < alignments.count,
            tableCell.colspan > 0, tableCell.rowspan > 0
        else { return }

        let element = inTableHead ? "th" : "td"
        out.emit("<")
        out.emitDynamic(element)
        if let alignment = alignments[currentTableColumn] {
            out.emit(" align=\"")
            out.emitDynamic(Self.alignmentName(alignment))
            out.emit("\"")
        }
        currentTableColumn += 1
        if tableCell.rowspan > 1 { out.emitDynamic(" rowspan=\"\(tableCell.rowspan)\"") }
        if tableCell.colspan > 1 { out.emitDynamic(" colspan=\"\(tableCell.colspan)\"") }
        out.emit(">")
        renderChildren(tableCell)
        out.emit("</")
        out.emitDynamic(element)
        out.emit(">\n")
    }

    // MARK: - helpers

    /// Apply the link resolver (if any) to a destination, falling back to the original URL.
    func resolvedURL(_ destination: String?) -> String? {
        guard let destination else { return nil }
        return linkResolver?(destination) ?? destination
    }

    /// Escape `value` for `context` through ADHTMLCore's audited encoder, writing the escaped bytes
    /// STRAIGHT into the shared `out` — the renderer's SINGLE escaping path (text, attribute, and URL all
    /// route here), so nothing reaches the output unescaped and no per-leaf `String` is materialized.
    mutating func escape(_ value: String, _ context: EscapeContext) {
        Escaper.write(value, context: context, into: &out)
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

// Literal / dynamic byte appenders for the shared accumulator — built on `ArraySink`'s own
// `write(_: UnsafeBufferPointer<UInt8>)` (visible via the struct import), so they need no extra import and
// materialize no intermediate `String`. `emit` takes a compile-time-constant `StaticString` (tags, fixed
// attribute fragments); `emitDynamic` takes an interpolated `String` (counts, element names) whose UTF-8
// is already safe in context.
extension ArraySink {
    fileprivate mutating func emit(_ literal: StaticString) {
        literal.withUTF8Buffer { write($0) }
    }

    fileprivate mutating func emitDynamic(_ string: String) {
        var copy = string
        copy.withUTF8 { write($0) }
    }
}
