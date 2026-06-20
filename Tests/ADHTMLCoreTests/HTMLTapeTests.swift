// Gate for the byte-level tape tokenizer (`HTMLTape`). It must materialize to EXACTLY the tokens the
// reference `HTMLTokenizer` produces — so the same oracle (tags + attributes, character references,
// comments, DOCTYPE, raw-text vs RCDATA) covers both, and a differential check pins them together on
// a mixed document. The tape is the fast path tree construction walks; the reference is the oracle.

import Testing

@testable import ADHTMLCore

struct HTMLTapeTests {
    private func tape(_ html: String) -> [HTMLToken] { HTMLTape.build(html).materialize() }

    @Test func tagsAndAttributes() {
        #expect(
            tape("<a href=\"x\" class='y' disabled>text</a>") == [
                .startTag(
                    name: "a",
                    attributes: [
                        .init(name: "href", value: "x"), .init(name: "class", value: "y"),
                        .init(name: "disabled", value: ""),
                    ], selfClosing: false),
                .text("text"),
                .endTag(name: "a"),
            ])
    }

    @Test func selfClosingTag() {
        #expect(tape("<br/>") == [.startTag(name: "br", attributes: [], selfClosing: true)])
    }

    @Test func characterReferencesDecodeInText() {
        #expect(tape("Hello &amp; &lt;world&gt; &#65;&#x42;") == [.text("Hello & <world> AB")])
    }

    @Test func commentToken() {
        #expect(tape("<!-- c -->") == [.comment(" c ")])
    }

    @Test func doctypeToken() {
        #expect(tape("<!DOCTYPE html>") == [.doctype(name: "html")])
    }

    @Test func scriptContentIsRawText() {
        #expect(
            tape("<script>if (a<b) x('</p>')</script>") == [
                .startTag(name: "script", attributes: [], selfClosing: false),
                .text("if (a<b) x('</p>')"),
                .endTag(name: "script"),
            ])
    }

    @Test func styleContentIsRawText() {
        #expect(
            tape("<style>a{color:red}</style>") == [
                .startTag(name: "style", attributes: [], selfClosing: false),
                .text("a{color:red}"),
                .endTag(name: "style"),
            ])
    }

    @Test func titleIsRCDATA() {
        #expect(
            tape("<title>A &amp; B</title>") == [
                .startTag(name: "title", attributes: [], selfClosing: false),
                .text("A & B"),
                .endTag(name: "title"),
            ])
    }

    /// Differential oracle: on a document mixing every construct, the tape must equal the reference.
    @Test func matchesReferenceTokenizerOnMixedDocument() {
        let html =
            "<!DOCTYPE html><html lang=\"en\"><head><title>T &amp; U</title>"
            + "<meta charset='utf-8'></head><body class=\"main\" data-x>"
            + "<h1 id='x'>Hi &lt;there&gt; &#9731;</h1><p>line<br/>two</p>"
            + "<script>if(a<b){x('</p>')}</script><style>.c{color:red}</style>"
            + "<!-- a note --><ul><li>one</li><li>two</li></ul></body></html>"
        #expect(HTMLTape.build(html).materialize() == HTMLTokenizer.tokenize(html))
    }

    /// The tape index accessor agrees with the bulk materialization.
    @Test func tokenAtMatchesMaterialize() {
        let built = HTMLTape.build("<p class=\"a\">hi</p>")
        let bulk = built.materialize()
        #expect(built.count == bulk.count)
        for i in 0 ..< built.count { #expect(built.token(at: i) == bulk[i]) }
    }
}
