// A full-page convenience (RFC-0005 §3.6). `Page` assembles `<!doctype html><html lang><head>…</head>
// <body>…</body></html>` from a head slot + a content slot, so an author never hand-writes the
// document scaffold — and never hits the `<body>`-element / `Component.body` name collision (a full-page
// `Component` can't render `<body>`: the element function is shadowed by the protocol's `body` property,
// and the module-qualified form is shadowed by the `ADHTMLCore` namespace enum). `Page` is a free
// function, so inside it `head`/`body` resolve to the element functions cleanly.

/// Assemble a complete HTML document from a `head` slot and a `content` (body) slot.
///
/// ```swift
/// Page(head: {
///     title { "Shop" }
///     meta().attribute("charset", "utf-8")
/// }) {
///     h1 { "Shop" }
///     // …
/// }
/// ```
public func Page<HeadContent: HTML, BodyContent: HTML>(
    lang: String = "en",
    @HTMLBuilder head headContent: () -> HeadContent,
    @HTMLBuilder content: () -> BodyContent
) -> some HTML {
    HTMLDocument {
        html {
            head { headContent() }
            body { content() }
        }
        .lang(lang)
    }
}
