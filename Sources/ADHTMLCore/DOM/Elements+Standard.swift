// Element constructors for the standard tag set (Tags+Standard.swift). Paired elements take builder
// content; void elements take none.

@inlinable public func html<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Html, C> { .init(content: c()) }
@inlinable public func head<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Head, C> { .init(content: c()) }
@inlinable public func body<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Body, C> { .init(content: c()) }
@inlinable public func title<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Title, C> { .init(content: c()) }
@inlinable public func style<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Style, C> { .init(content: c()) }
@inlinable public func script<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Script, C> { .init(content: c()) }

@inlinable public func h1<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.H1, C> { .init(content: c()) }
@inlinable public func h2<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.H2, C> { .init(content: c()) }
@inlinable public func h3<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.H3, C> { .init(content: c()) }
@inlinable public func h4<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.H4, C> { .init(content: c()) }
@inlinable public func h5<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.H5, C> { .init(content: c()) }
@inlinable public func h6<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.H6, C> { .init(content: c()) }

@inlinable public func nav<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Nav, C> { .init(content: c()) }
@inlinable public func header<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Header, C> { .init(content: c()) }
@inlinable public func footer<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Footer, C> { .init(content: c()) }
@inlinable public func main<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Main, C> { .init(content: c()) }
@inlinable public func section<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Section, C> {
    .init(content: c())
}
@inlinable public func article<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Article, C> {
    .init(content: c())
}

@inlinable public func ul<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Ul, C> { .init(content: c()) }
@inlinable public func ol<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Ol, C> { .init(content: c()) }
@inlinable public func li<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Li, C> { .init(content: c()) }

@inlinable public func strong<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Strong, C> { .init(content: c()) }
@inlinable public func em<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Em, C> { .init(content: c()) }
@inlinable public func code<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Code, C> { .init(content: c()) }
@inlinable public func pre<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Pre, C> { .init(content: c()) }
@inlinable public func label<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Label, C> { .init(content: c()) }

@inlinable public func form<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Form, C> { .init(content: c()) }
@inlinable public func textarea<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Textarea, C> {
    .init(content: c())
}
@inlinable public func select<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Select, C> { .init(content: c()) }
@inlinable public func option<C: HTML>(@HTMLBuilder _ c: () -> C) -> HTMLElement<Tags.Option, C> { .init(content: c()) }

// Void elements
@inlinable public func meta() -> HTMLElement<Tags.Meta, EmptyHTML> { .init(content: EmptyHTML()) }
@inlinable public func link() -> HTMLElement<Tags.Link, EmptyHTML> { .init(content: EmptyHTML()) }
@inlinable public func input() -> HTMLElement<Tags.Input, EmptyHTML> { .init(content: EmptyHTML()) }
@inlinable public func img() -> HTMLElement<Tags.Img, EmptyHTML> { .init(content: EmptyHTML()) }
@inlinable public func hr() -> HTMLElement<Tags.Hr, EmptyHTML> { .init(content: EmptyHTML()) }
