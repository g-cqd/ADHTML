// Document/head conveniences (RFC-0005 §3.6) — small, typed helpers over the raw element constructors so
// a page head reads cleanly: `meta().charset()`, `Viewport()`, `Stylesheet("/app.css")`. Each returns a
// concrete element, so they compose inside an `@HTMLBuilder` head slot (e.g. `Page(head:)`).

extension HTMLElement where Tag == Tags.Meta {
    /// `<meta charset="utf-8">` — the charset every document should declare.
    public consuming func charset(_ value: String = "utf-8") -> Self { attribute("charset", value) }
}

/// `<meta name="viewport" content="…">` — defaults to the standard responsive viewport.
public func Viewport(_ content: String = "width=device-width, initial-scale=1")
    -> HTMLElement<Tags.Meta, EmptyHTML>
{
    meta().name("viewport").content(content)
}

/// `<link rel="stylesheet" href="…">`.
public func Stylesheet(_ href: String) -> HTMLElement<Tags.Link, EmptyHTML> {
    link().rel(.stylesheet).href(href)
}

/// `<link rel="icon" href="…">` — a favicon link.
public func Favicon(_ href: String) -> HTMLElement<Tags.Link, EmptyHTML> {
    link().rel(.icon).href(href)
}
