// Gate for HTML -> plain text / Markdown extraction (the native replacement for the JS crawl's
// regex converters). Covers emphasis, headings, links (+ resolver), lists (including links inside
// items, which the regex version dropped), inline/block code, blockquote, images, chrome stripping,
// and inline-whitespace collapsing.

import Testing

@testable import ADHTMLCore

struct HTMLMarkdownTests {
    private func md(_ html: String, linkResolver: ((String) -> String?)? = nil) -> String {
        HTMLNode.parse(html).markdown(linkResolver: linkResolver)
    }
    private func txt(_ html: String) -> String { HTMLNode.parse(html).plainText() }

    @Test func inlineEmphasis() {
        #expect(md("<p>Hello <strong>world</strong> and <em>you</em></p>") == "Hello **world** and *you*")
    }

    @Test func heading() {
        #expect(md("<h2>Title</h2><p>Body</p>") == "## Title\n\nBody")
    }

    @Test func link() {
        #expect(md("<p>see <a href=\"/x\">the docs</a></p>") == "see [the docs](/x)")
    }

    @Test func namedAnchorKeepsTextOnly() {
        #expect(md("<p>see <a name=\"top\">top</a></p>") == "see top")
    }

    @Test func unorderedList() {
        #expect(md("<ul><li>a</li><li>b</li></ul>") == "- a\n- b")
    }

    @Test func orderedList() {
        #expect(md("<ol><li>one</li><li>two</li></ol>") == "1. one\n2. two")
    }

    @Test func linkInsideListItem() {
        // The regex converter dropped links in list items; the DOM walk keeps them.
        #expect(md("<ul><li><a href=\"/x\">y</a> tail</li></ul>") == "- [y](/x) tail")
    }

    @Test func inlineCode() {
        #expect(md("<p>call <code>foo()</code> now</p>") == "call `foo()` now")
    }

    @Test func preBecomesFencedCode() {
        #expect(md("<pre>let x = 1\nlet y = 2</pre>") == "```\nlet x = 1\nlet y = 2\n```")
    }

    @Test func blockquote() {
        #expect(md("<blockquote><p>quoted</p></blockquote>") == "> quoted")
    }

    @Test func horizontalRule() {
        #expect(md("<p>a</p><hr><p>b</p>") == "a\n\n---\n\nb")
    }

    @Test func image() {
        #expect(md("<p><img src=\"/i.png\" alt=\"pic\"></p>") == "![pic](/i.png)")
    }

    @Test func stripsScriptAndChrome() {
        #expect(md("<p>keep</p><script>var x=1</script><p>this</p>") == "keep\n\nthis")
        #expect(txt("<nav>menu</nav><p>body text</p>") == "body text")
    }

    @Test func plainTextSeparatesBlocksAndCollapsesInlineWhitespace() {
        #expect(txt("<div><p>first para</p><p>second para</p></div>") == "first para\n\nsecond para")
        // A newline inside a paragraph is inline whitespace → a space, not a line break.
        #expect(txt("<p>  lots   of\n   space  </p>") == "lots of space")
    }

    @Test func linkResolverRewritesAndDrops() {
        #expect(md("<a href=\"old\">t</a>", linkResolver: { _ in "new" }) == "[t](new)")
        #expect(md("<a href=\"x\">t</a>", linkResolver: { _ in nil }) == "t")
    }

    @Test func nestedListFlattensIntoItem() {
        // A nested <ul> inside an <li> renders inline within that item (one line per top-level item).
        #expect(md("<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>") == "- a - b\n- c")
    }
}
