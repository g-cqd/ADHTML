import Testing

@testable import ADHTMLCore

@Suite("Standard elements")
struct ElementsTests {
    @Test("a realistic page renders with document, sectioning, list, and form elements")
    func realisticPage() {
        let page =
            html {
                head {
                    title { "Hi" }
                    meta().attribute("charset", "utf-8")
                }
                body {
                    nav { a { "Home" }.href("/") }
                    main {
                        h1 { "Title" }
                        ul {
                            li { "a" }
                            li { "b" }
                        }
                    }
                }
            }
            .lang("en")
            .render()

        #expect(page.hasPrefix(#"<html lang="en"><head><title>Hi</title><meta charset="utf-8">"#))
        #expect(page.contains(#"<nav><a href="/">Home</a></nav>"#))
        #expect(page.contains("<ul><li>a</li><li>b</li></ul>"))
        #expect(page.hasSuffix("</main></body></html>"))
    }

    @Test("void elements emit no closing tag")
    func voidElements() {
        #expect(img().src("/logo.png").alt("Logo").render() == #"<img src="/logo.png" alt="Logo">"#)
        #expect(hr().render() == "<hr>")
        #expect(
            input().type("text").name("q").placeholder("Search").render()
                == #"<input type="text" name="q" placeholder="Search">"#)
    }

    @Test("trait-gated attributes render; global attributes apply anywhere")
    func attributes() {
        #expect(label { "Name" }.htmlFor("n").render() == #"<label for="n">Name</label>"#)
        #expect(input().disabled().render() == #"<input disabled="">"#)
        #expect(
            div {}.data("count", "3").aria("live", "polite").render()
                == #"<div data-count="3" aria-live="polite"></div>"#)
        #expect(span { "x" }.hidden().title("t").render() == #"<span hidden="" title="t">x</span>"#)
    }
}
