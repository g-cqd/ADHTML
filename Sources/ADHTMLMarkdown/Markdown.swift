// `Markdown` — write Markdown inside a component body (as a Swift string or a result-builder block) and
// EMBED live ADHTML components in the prose, rendered to HTML with escape-by-default and FULL hydration.
//
// How a slot keeps full island fidelity (the render-thunk): `ADHTMLMarkdown.render` runs once over the
// source (sentinels and all), then `_render` splits the rendered HTML on the sentinels and interleaves
// `target.raw(segment)` with each slot rendered INTO the page target via `RenderTarget._embedMarkdownSlot`.
// Because a `Component`'s `_render` writes its island ops onto WHATEVER target it is handed, rendering a
// slot into the page `HTMLProgram` lands its `islandOpen`/`islandClose` exactly where `renderHydratable`'s
// island scan finds them — so an embedded `@State`/`@Component` island hydrates as if placed directly in
// the body, with zero change to the wire serializer. The static path (`render()`) renders slots inline.
public import struct ADHTMLCore.ArraySink
public import struct ADHTMLCore.DirectTarget
public import protocol ADHTMLCore.HTML
public import struct ADHTMLCore.HTMLProgram
public import protocol ADHTMLCore.RenderTarget

/// Markdown content (with embedded components) as an ``HTML`` node. Author it as a string with typed
/// interpolations — `Markdown("# \(title)\n\nBuy: \(BuyButton(sku))")` — or as a `@MarkdownBuilder` block
/// for control flow — `Markdown { "# Title"; if hot { Badge("HOT") }; for x in xs { "- \(x.name)" } }`.
public struct Markdown: HTML {
    let content: MarkdownContent

    /// Author Markdown as a string literal with typed interpolations (the template-literal form).
    public init(_ string: MarkdownString, allowRawHTML: Bool = false) {
        var content = string.content
        content.allowRawHTML = content.allowRawHTML || allowRawHTML
        self.content = content
    }

    /// Author Markdown as a `@MarkdownBuilder` block (Markdown fragments + components + control flow).
    public init(allowRawHTML: Bool = false, @MarkdownBuilder _ build: () -> MarkdownContent) {
        var content = build()
        content.allowRawHTML = content.allowRawHTML || allowRawHTML
        self.content = content
    }

    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        let rendered = ADHTMLMarkdown.render(
            html.content.source,
            linkResolver: html.content.linkResolver,
            allowRawHTML: html.content.allowRawHTML)

        var segments = split(rendered, slotCount: html.content.slots.count)
        unwrapLoneParagraphs(&segments)

        let slots = html.content.slots
        for segment in segments {
            if !segment.text.isEmpty { target.raw(Array(segment.text.utf8)) }
            if let index = segment.slotIndex, index < slots.count {
                target._embedMarkdownSlot(program: slots[index].program, direct: slots[index].direct)
            }
        }
    }

    /// One emitted piece: a run of rendered HTML, optionally followed by the slot whose sentinel ended it.
    private struct Segment {
        var text: String
        var slotIndex: Int?
    }

    /// Split rendered HTML on the slot sentinels: each in-range PUA scalar closes the current text run and
    /// records its slot index; the trailing run has no slot. Robust to slot reordering by the renderer
    /// (each sentinel carries its own index), though normal Markdown preserves source order.
    private static func split(_ html: String, slotCount: Int) -> [Segment] {
        var segments: [Segment] = []
        var buffer = String.UnicodeScalarView()
        for scalar in html.unicodeScalars {
            if let index = MarkdownContent.slotIndex(of: scalar, slotCount: slotCount) {
                segments.append(Segment(text: String(buffer), slotIndex: index))
                buffer = String.UnicodeScalarView()
            } else {
                buffer.append(scalar)
            }
        }
        segments.append(Segment(text: String(buffer), slotIndex: nil))
        return segments
    }

    /// Unwrap the `<p>…</p>` the renderer wraps around a slot that is ALONE in its paragraph (a block
    /// component on its own line): when the text just before a slot ends with `<p>` and the text just
    /// after begins with `</p>`, strip both — `<p><div>…</div></p>` is invalid HTML the browser would
    /// auto-split. A slot used inline in prose keeps its wrapper (the surrounding text is not bare `<p>`).
    private static func unwrapLoneParagraphs(_ segments: inout [Segment]) {
        for index in segments.indices where segments[index].slotIndex != nil {
            guard index + 1 < segments.count,
                segments[index].text.hasSuffix("<p>"),
                segments[index + 1].text.hasPrefix("</p>")
            else {
                continue
            }
            segments[index].text.removeLast(3)  // "<p>"
            segments[index + 1].text.removeFirst(4)  // "</p>"
        }
    }
}
