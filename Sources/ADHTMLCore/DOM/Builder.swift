// The result builder and its product types. `buildPartialBlock` (SE-0348) gives unbounded child arity
// with **zero `any`** and a single small pair type — children accumulate left-nested as
// `_HTMLPair`s, and each pair lowers its left then its right (separate statements → no exclusivity
// hazard). Optionals/either/array cover `if`/`if-else`/`for` in a builder block.

/// Builds ``HTML`` content from a block of child nodes and string literals.
@resultBuilder
public enum HTMLBuilder {
    public static func buildExpression(_ text: String) -> Text { Text(text) }
    public static func buildExpression<Content: HTML>(_ content: Content) -> Content { content }

    public static func buildBlock() -> EmptyHTML { EmptyHTML() }
    public static func buildPartialBlock<Content: HTML>(first: Content) -> Content { first }
    public static func buildPartialBlock<L: HTML, R: HTML>(accumulated: L, next: R) -> _HTMLPair<L, R> {
        _HTMLPair(accumulated, next)
    }

    public static func buildOptional<Content: HTML>(_ content: Content?) -> _HTMLOptional<Content> {
        _HTMLOptional(content)
    }
    public static func buildEither<First: HTML, Second: HTML>(first: First) -> _HTMLEither<First, Second> {
        .first(first)
    }
    public static func buildEither<First: HTML, Second: HTML>(second: Second) -> _HTMLEither<First, Second> {
        .second(second)
    }
    public static func buildArray<Content: HTML>(_ components: [Content]) -> _HTMLArray<Content> {
        _HTMLArray(components)
    }
}

/// The empty node — emits nothing.
public struct EmptyHTML: HTML {
    public init() {}
    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {}
}

/// Two adjacent nodes (the result-builder accumulator). Lowers left then right.
public struct _HTMLPair<Left: HTML, Right: HTML>: HTML {
    public let left: Left
    public let right: Right
    @inlinable public init(_ left: Left, _ right: Right) {
        self.left = left
        self.right = right
    }
    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        Left._render(html.left, into: &target)
        Right._render(html.right, into: &target)
    }
}

/// An optional node (`if` without `else`).
public struct _HTMLOptional<Wrapped: HTML>: HTML {
    public let wrapped: Wrapped?
    @inlinable public init(_ wrapped: Wrapped?) { self.wrapped = wrapped }
    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        if let wrapped = html.wrapped { Wrapped._render(wrapped, into: &target) }
    }
}

/// One of two node types (`if`/`else`).
public enum _HTMLEither<First: HTML, Second: HTML>: HTML {
    case first(First)
    case second(Second)
    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        switch html {
            case .first(let first): First._render(first, into: &target)
            case .second(let second): Second._render(second, into: &target)
        }
    }
}

/// A homogeneous sequence of nodes (`for` in a builder block). Lowered by an iterative loop.
public struct _HTMLArray<Element: HTML>: HTML {
    public let elements: [Element]
    @inlinable public init(_ elements: [Element]) { self.elements = elements }
    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        for element in html.elements { Element._render(element, into: &target) }
    }
}
