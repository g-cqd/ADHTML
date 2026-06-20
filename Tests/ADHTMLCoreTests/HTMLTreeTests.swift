// Gate for tree construction (`HTMLNode.parse` / `HTMLTape.tree`): the tokenizer's flat stream folds
// into the nested DOM with the pragmatic WHATWG subset the crawl needs — void elements, implied end
// tags (list items, table cells/rows, omitted `</p>`), scoped auto-closing (a nested list's `<li>`
// must not close the outer one), stray-end-tag recovery, and adjacent-text coalescing.

import Testing

@testable import ADHTMLCore

struct HTMLTreeTests {
    private func el(_ tag: String, _ attrs: [String: String] = [:], _ children: [HTMLNode] = [])
        -> HTMLNode
    { .element(tag: tag, attributes: attrs, children: children) }

    @Test func nestsElements() {
        #expect(
            HTMLNode.parse("<div><p>hi</p></div>") == [el("div", [:], [el("p", [:], [.text("hi")])])])
    }

    @Test func voidElementsTakeNoChildren() {
        #expect(
            HTMLNode.parse("<div><br><span>x</span></div>")
                == [el("div", [:], [el("br"), el("span", [:], [.text("x")])])])
    }

    @Test func selfClosingTakesNoChildren() {
        #expect(
            HTMLNode.parse("<div><img src=\"a\"/>t</div>")
                == [el("div", [:], [el("img", ["src": "a"]), .text("t")])])
    }

    @Test func impliedListItemClose() {
        #expect(
            HTMLNode.parse("<ul><li>a<li>b</ul>")
                == [el("ul", [:], [el("li", [:], [.text("a")]), el("li", [:], [.text("b")])])])
    }

    @Test func nestedListDoesNotCloseOuterItem() {
        // The inner list's <li> must stay inside the outer <li>, not become its sibling.
        #expect(
            HTMLNode.parse("<ul><li>a<ul><li>b</ul></li></ul>")
                == [
                    el(
                        "ul", [:],
                        [el("li", [:], [.text("a"), el("ul", [:], [el("li", [:], [.text("b")])])])])
                ])
    }

    @Test func blockElementClosesOpenParagraph() {
        #expect(
            HTMLNode.parse("<p>a<div>b</div>")
                == [el("p", [:], [.text("a")]), el("div", [:], [.text("b")])])
    }

    @Test func impliedTableCellsAndRows() {
        #expect(
            HTMLNode.parse("<table><tr><td>a<td>b<tr><td>c</table>")
                == [
                    el(
                        "table", [:],
                        [
                            el(
                                "tr", [:],
                                [el("td", [:], [.text("a")]), el("td", [:], [.text("b")])]),
                            el("tr", [:], [el("td", [:], [.text("c")])])
                        ])
                ])
    }

    @Test func strayEndTagIsIgnored() {
        #expect(HTMLNode.parse("<div>x</span></div>") == [el("div", [:], [.text("x")])])
    }

    @Test func unclosedElementsCloseAtEnd() {
        // <p> nests inside the still-open <h1> (the parser doesn't enforce content models); both close
        // at EOF.
        #expect(
            HTMLNode.parse("<section><h1>Title<p>Body")
                == [el("section", [:], [el("h1", [:], [.text("Title"), el("p", [:], [.text("Body")])])])])
    }

    @Test func keepsFirstOfDuplicateAttributes() {
        #expect(HTMLNode.parse("<a id=\"x\" id=\"y\">z</a>") == [el("a", ["id": "x"], [.text("z")])])
    }

    @Test func coalescesAdjacentTextAroundEntities() {
        // "a" + decoded "&" + "b" arrive as one text run from the tape; a comment splits text nodes.
        #expect(
            HTMLNode.parse("<p>a<!--c-->b</p>")
                == [el("p", [:], [.text("a"), .comment("c"), .text("b")])])
    }

    @Test func accessorsWalkTheParsedTree() {
        let article =
            HTMLNode.parse(
                "<article><h1>T</h1><p>one <a href=\"/x\">two</a> three</p></article>"
            )
            .first
        #expect(article?.textContent == "Tone two three")
        #expect(article?.elements(tag: "a").first?.attribute("href") == "/x")
        #expect(article?.firstElement(tag: "h1")?.textContent == "T")
    }

    @Test func impliedDefinitionListAndOptionClose() {
        #expect(
            HTMLNode.parse("<dl><dt>a<dd>b<dt>c</dl>")
                == [
                    el(
                        "dl", [:],
                        [
                            el("dt", [:], [.text("a")]), el("dd", [:], [.text("b")]),
                            el("dt", [:], [.text("c")])
                        ])
                ])
        #expect(
            HTMLNode.parse("<select><option>a<option>b</select>")
                == [
                    el(
                        "select", [:],
                        [el("option", [:], [.text("a")]), el("option", [:], [.text("b")])])
                ])
    }

    @Test func tableSectionImpliedClose() {
        #expect(
            HTMLNode.parse("<table><thead><tr><td>h</table>")
                == [
                    el(
                        "table", [:],
                        [el("thead", [:], [el("tr", [:], [el("td", [:], [.text("h")])])])])
                ])
    }
}
