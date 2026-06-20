import ADHTML

// The page shell is a FREE FUNCTION, not a `@Component`, on purpose: a full-page layout must render the
// `<body>` element, whose function name collides with the `Component.body` property inside a component
// (and the module-qualified form is shadowed by the `ADHTMLCore` namespace enum). So the shell is a
// function — where bare `body { … }` is the element — while content + interactive pieces are `@Component`s.
// It still composes via a "slot": an `@HTMLBuilder` parameter for the page's children. (A `.bodyElement`
// alias to let full-page components exist is a tracked DSL follow-up.)
func pageLayout<Content: HTML>(pageTitle: String, @HTMLBuilder content: () -> Content) -> some HTML {
    html {
        head {
            meta().attribute("charset", "utf-8")
            meta().name("viewport").content("width=device-width, initial-scale=1")
            title { pageTitle }
            link().rel(.stylesheet).href("/app.css")
        }
        body {
            nav {
                a { "Acme Tools" }.href("/").class("brand")
                a { "Cart" }.href("/cart")
            }
            .role(.navigation)
            main { content() }  // the slot
            footer { p { "© 2026 Acme" } }
        }
    }
    .lang("en")
}
