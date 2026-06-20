/// A complete HTML document: a `<!doctype html>` prefix followed by its content (typically `<html>`).
/// A small convenience the umbrella adds over the engine; renders via the same iterative path.
public struct HTMLDocument<Content: HTML>: HTML {
    public let content: Content
    public init(@HTMLBuilder _ content: () -> Content) { self.content = content() }
    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        target.raw(Array("<!doctype html>".utf8))
        Content._render(html.content, into: &target)
    }
}
