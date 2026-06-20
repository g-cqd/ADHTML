// The result-builder authoring surface: `Markdown { … }`. Statements are author-trusted Markdown `String`
// fragments (→ Markdown source) and `some HTML` components (→ slots), with the usual control flow
// (`if`/`if-else`/`for`/optional via buildOptional/Either/Array). Fragments JOIN WITH `\n`, so a `for`
// over list-item strings yields one list, and a heading followed by a component yields a heading then the
// component. It is what the string form cannot express:
//   Markdown { "# Title"; if hot { Badge("HOT") }; for item in items { "- \(item.name)" } }
public import protocol ADHTMLCore.HTML

/// Builds a ``MarkdownContent`` from a mix of Markdown fragments, components, and control flow.
@resultBuilder
public enum MarkdownBuilder {
    /// A Markdown `String` fragment — author-trusted source.
    public static func buildExpression(_ markdown: String) -> MarkdownContent {
        var content = MarkdownContent()
        content.appendMarkdown(markdown)
        return content
    }

    /// A component — embedded as a slot (full hydration fidelity). A nested `Markdown` is `some HTML`, so
    /// it embeds here and renders by recursion.
    public static func buildExpression(_ component: some HTML) -> MarkdownContent {
        var content = MarkdownContent()
        content.appendSlot(MarkdownSlot(component))
        return content
    }

    public static func buildBlock(_ parts: MarkdownContent...) -> MarkdownContent { join(parts) }
    public static func buildArray(_ parts: [MarkdownContent]) -> MarkdownContent { join(parts) }
    public static func buildOptional(_ part: MarkdownContent?) -> MarkdownContent { part ?? MarkdownContent() }
    public static func buildEither(first: MarkdownContent) -> MarkdownContent { first }
    public static func buildEither(second: MarkdownContent) -> MarkdownContent { second }
    public static func buildLimitedAvailability(_ part: MarkdownContent) -> MarkdownContent { part }

    /// Concatenate the non-empty pieces, inserting `\n` between them and remapping each piece's slot
    /// sentinels so the merged slot list stays index-consistent.
    static func join(_ parts: [MarkdownContent]) -> MarkdownContent {
        var result = MarkdownContent()
        var isFirst = true
        for part in parts where !(part.source.isEmpty && part.slots.isEmpty) {
            if !isFirst { result.appendMarkdown("\n") }
            isFirst = false
            result.appendContent(part)
        }
        return result
    }
}
