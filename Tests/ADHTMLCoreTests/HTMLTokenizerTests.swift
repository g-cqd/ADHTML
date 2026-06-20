// Gate for the pure-Swift WHATWG HTML tokenizer. Covers tags + attributes, character
// references, comments, DOCTYPE, and the cases a real parser gets right where regex
// can't: raw-text (<script>/<style>) content is NOT parsed as markup, and RCDATA
// (<title>) decodes entities without parsing markup.

import Testing

@testable import ADHTMLCore

struct HTMLTokenizerTests {
    @Test func tagsAndAttributes() {
        let tokens = HTMLTokenizer.tokenize("<a href=\"x\" class='y' disabled>text</a>")
        #expect(
            tokens == [
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
        #expect(HTMLTokenizer.tokenize("<br/>") == [.startTag(name: "br", attributes: [], selfClosing: true)])
    }

    @Test func characterReferencesDecodeInText() {
        let tokens = HTMLTokenizer.tokenize("Hello &amp; &lt;world&gt; &#65;&#x42;")
        #expect(tokens == [.text("Hello & <world> AB")])
    }

    @Test func commentToken() {
        #expect(HTMLTokenizer.tokenize("<!-- c -->") == [.comment(" c ")])
    }

    @Test func doctypeToken() {
        #expect(HTMLTokenizer.tokenize("<!DOCTYPE html>") == [.doctype(name: "html")])
    }

    @Test func scriptContentIsRawText() {
        // The `<b` and `</p>` inside <script> are TEXT, not tags.
        let tokens = HTMLTokenizer.tokenize("<script>if (a<b) x('</p>')</script>")
        #expect(
            tokens == [
                .startTag(name: "script", attributes: [], selfClosing: false),
                .text("if (a<b) x('</p>')"),
                .endTag(name: "script"),
            ])
    }

    @Test func styleContentIsRawText() {
        let tokens = HTMLTokenizer.tokenize("<style>a{color:red}</style>")
        #expect(
            tokens == [
                .startTag(name: "style", attributes: [], selfClosing: false),
                .text("a{color:red}"),
                .endTag(name: "style"),
            ])
    }

    @Test func titleIsRCDATA() {
        // <title> is RCDATA: entities decode, but markup does not parse.
        let tokens = HTMLTokenizer.tokenize("<title>A &amp; B</title>")
        #expect(
            tokens == [
                .startTag(name: "title", attributes: [], selfClosing: false),
                .text("A & B"),
                .endTag(name: "title"),
            ])
    }
}
