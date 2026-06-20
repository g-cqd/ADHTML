// Gate for ADHTMLMarkdown (the Markdown → HTML renderer). Renders fixtures across the block + inline
// vocabulary and asserts structure-equivalent HTML, with a sharp focus on the escape-by-default contract:
// text, attributes, and URLs all route through ADHTMLCore's `Escaper`, so untrusted Markdown cannot inject
// markup or a dangerous URL, and raw HTML is shown literally unless explicitly allowed.

import Testing

@testable import ADHTMLMarkdown

@Suite("ADHTMLMarkdown — Markdown → escaped HTML")
struct ADHTMLMarkdownTests {
    @Test("headings render h1…h6")
    func headings() {
        #expect(ADHTMLMarkdown.render("# One") == "<h1>One</h1>\n")
        let all = ADHTMLMarkdown.render("# a\n## b\n### c\n#### d\n##### e\n###### f")
        for (level, text) in [(1, "a"), (2, "b"), (3, "c"), (4, "d"), (5, "e"), (6, "f")] {
            #expect(all.contains("<h\(level)>\(text)</h\(level)>"))
        }
    }

    @Test("paragraph with emphasis, strong, strikethrough, inline code")
    func inlineFormatting() {
        let html = ADHTMLMarkdown.render("*em* and **strong** and ~~gone~~ and `code()`")
        #expect(html.contains("<em>em</em>"))
        #expect(html.contains("<strong>strong</strong>"))
        #expect(html.contains("<del>gone</del>"))  // GFM strikethrough (cmark-gfm default)
        #expect(html.contains("<code>code()</code>"))
        #expect(html.hasPrefix("<p>"))
    }

    @Test("unordered + ordered lists, ordered start attribute")
    func lists() {
        let ul = ADHTMLMarkdown.render("- a\n- b")
        #expect(ul.contains("<ul>"))
        #expect(ul.contains("</ul>"))
        #expect(ul.contains("<li>"))
        #expect(ul.contains("a"))
        #expect(ul.contains("b"))

        let ol = ADHTMLMarkdown.render("3. x\n4. y")
        #expect(ol.contains("<ol start=\"3\">"))

        // A default-start (1) ordered list omits the attribute.
        #expect(ADHTMLMarkdown.render("1. only").contains("<ol>"))
    }

    @Test("GFM task-list checkboxes")
    func taskList() {
        let html = ADHTMLMarkdown.render("- [x] done\n- [ ] todo")
        #expect(html.contains("<input type=\"checkbox\" disabled=\"\" checked=\"\" /> "))
        #expect(html.contains("<input type=\"checkbox\" disabled=\"\" /> "))
    }

    @Test("fenced code carries a language class and escapes its content")
    func fencedCode() {
        let html = ADHTMLMarkdown.render("```swift\nlet x = \"<a>\" & 1\n```")
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("</code></pre>"))
        // The code body is escaped (`<` `>` `&`), never emitted as live markup.
        #expect(html.contains("&lt;a&gt;"))
        #expect(html.contains("&amp;"))
        #expect(!html.contains("<a>"))
    }

    @Test("blockquote")
    func blockquote() {
        let html = ADHTMLMarkdown.render("> quoted")
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("quoted"))
        #expect(html.contains("</blockquote>"))
    }

    @Test("thematic break")
    func thematicBreak() {
        #expect(ADHTMLMarkdown.render("a\n\n---\n\nb").contains("<hr />"))
    }

    @Test("links pass through the resolver and are URL-escaped")
    func links() {
        #expect(ADHTMLMarkdown.render("[text](/path)").contains("<a href=\"/path\">text</a>"))

        let resolved = ADHTMLMarkdown.render(
            "[text](/path)", linkResolver: { $0 == "/path" ? "/resolved" : nil })
        #expect(resolved.contains("<a href=\"/resolved\">text</a>"))

        // Ampersands in the destination are attribute-escaped.
        #expect(ADHTMLMarkdown.render("[q](/s?a=1&b=2)").contains("href=\"/s?a=1&amp;b=2\""))
    }

    @Test("a dangerous URL scheme is neutralized, not emitted")
    func dangerousLinkNeutralized() {
        let html = ADHTMLMarkdown.render("[click](javascript:alert)")
        #expect(html.contains("<a href=\"#\">click</a>"))
        #expect(!html.contains("javascript:"))
    }

    @Test("images render src, alt, and title")
    func images() {
        let html = ADHTMLMarkdown.render("![the alt](/img.png \"a title\")")
        #expect(html.contains("<img"))
        #expect(html.contains("src=\"/img.png\""))
        #expect(html.contains("alt=\"the alt\""))
        #expect(html.contains("title=\"a title\""))
    }

    @Test("GFM table with column alignments")
    func table() {
        let markdown = """
            | H1 | H2 | H3 |
            | :-- | :-: | --: |
            | a | b | c |
            """
        let html = ADHTMLMarkdown.render(markdown)
        #expect(html.contains("<table>"))
        #expect(html.contains("<thead>"))
        #expect(html.contains("<th align=\"left\">H1</th>"))
        #expect(html.contains("<th align=\"center\">H2</th>"))
        #expect(html.contains("<th align=\"right\">H3</th>"))
        #expect(html.contains("<tbody>"))
        #expect(html.contains("<td align=\"left\">a</td>"))
        #expect(html.contains("<td align=\"center\">b</td>"))
        #expect(html.contains("<td align=\"right\">c</td>"))
    }

    @Test("text content is HTML-escaped (no injection)")
    func textEscaped() {
        let html = ADHTMLMarkdown.render("a < b & c > d")
        #expect(html.contains("a &lt; b &amp; c &gt; d"))
        #expect(!html.contains("a < b"))
    }

    @Test("raw HTML is escaped by default and passed through only when allowed")
    func rawHTML() {
        let blockDefault = ADHTMLMarkdown.render("<div>raw</div>")
        #expect(blockDefault.contains("&lt;div&gt;raw&lt;/div&gt;"))
        #expect(!blockDefault.contains("<div>raw</div>"))

        let blockAllowed = ADHTMLMarkdown.render("<div>raw</div>", allowRawHTML: true)
        #expect(blockAllowed.contains("<div>raw</div>"))

        // Inline raw HTML follows the same rule.
        #expect(ADHTMLMarkdown.render("text <b>x</b>").contains("&lt;b&gt;"))
    }

    @Test("soft and hard line breaks")
    func lineBreaks() {
        #expect(ADHTMLMarkdown.render("a\nb").contains("a\nb"))  // soft break → newline
        #expect(ADHTMLMarkdown.render("a  \nb").contains("<br />"))  // two trailing spaces → hard break
    }
}
