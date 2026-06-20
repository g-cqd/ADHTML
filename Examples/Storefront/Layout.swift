import ADHTML

// A reusable page shell — now a clean `@Component` with a children slot (an @HTMLBuilder init). It uses
// `Page(head:content:)` to assemble the document, so it never hand-writes `<html>`/`<head>`/`<body>` and
// never hits the `<body>`-element / `Component.body` collision (the reason this used to be a free
// function). No @State, so it stays static and renders inline (no island, no JS). Typed enums throughout.
@Component
struct PageLayout<Content: HTML> {
    let pageTitle: String
    let content: Content

    init(pageTitle: String, @HTMLBuilder content: () -> Content) {
        self.pageTitle = pageTitle
        self.content = content()
    }

    var body: some HTML {
        Page(
            head: {
                meta().attribute("charset", "utf-8")
                meta().name("viewport").content("width=device-width, initial-scale=1")
                title { pageTitle }
                link().rel(.stylesheet).href("/app.css")
            },
            content: {
                nav {
                    a { "Acme Tools" }.href("/").class("brand")
                    a { "Cart" }.href("/cart")
                }
                .role(.navigation)
                main { content }  // the slot
                footer { p { "© 2026 Acme" } }
            })
    }
}
