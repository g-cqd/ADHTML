// The two-protocol model (RFC-0002): `HTML` is the base — every node knows how to lower itself onto
// the flat opcode program. `Component` refines it with a `@HTMLBuilder var body`, exactly the
// SwiftUI `View`/`@ViewBuilder` pattern, so user views compose without ever touching the renderer.
// Lowering is the only protocol requirement; the *render walk* over the produced program is iterative
// (no recursion over a value tree) — see `Renderer`.

/// A node that can lower itself into an ``HTMLProgram``. Conformers are `Sendable` value types; the
/// lowering is static (monomorphized, zero `any`). Primitive nodes implement ``_render(_:into:)``
/// directly; composed views conform to ``Component`` instead and get it for free.
public protocol HTML: Sendable {
    /// Emit this node's render tokens into `target` (a `DirectTarget` for one-pass byte output, or an
    /// `HTMLProgram` for the materialized path). SPI — call ``render()``/``renderBytes()``, not this.
    static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target)
}

/// A composed view: its `body` is built with ``HTMLBuilder`` and lowered in its place. The
/// SwiftUI-style authoring surface — `struct Card: Component { var body: some HTML { … } }`.
public protocol Component: HTML {
    associatedtype Body: HTML
    @HTMLBuilder var body: Body { get }
    /// Set `true` by `@Component` when the type has `@State`/`@Derived`: the component then AUTO-WRAPS as a
    /// hydration island with an INFERRED scope, so the author writes no `Island`/`scope`/`.id`
    /// (RFC-0005 §3.0). Default `false` — a static component (and a manual `: Component` conformance)
    /// renders inline; an explicit `Island` in the body still works.
    static var isIsland: Bool { get }
    /// When the client runtime wires this component's island (only when `isIsland`). Default `.load`;
    /// override with `static var hydration: LoadStrategy { .visible }` for lazy wiring.
    static var hydration: LoadStrategy { get }
}

extension Component {
    public static var isIsland: Bool { false }
    public static var hydration: LoadStrategy { .load }

    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        // Pure static render (no hydration): render the body directly — zero reactive bookkeeping.
        guard let context = ADHTMLRenderContext.child() else {
            Body._render(html.body, into: &target)
            return
        }
        // Reactive render: push a fresh per-instance scope so this instance's `@State` cells are
        // distinct from any sibling's. `body` is evaluated INSIDE the scope (where `@State`/computed
        // reads register their cells); lowering the built value afterwards needs no context.
        let built = ADHTMLRenderContext.$current.withValue(context) { html.body }
        guard isIsland else {
            Body._render(built, into: &target)
            return
        }
        // An interactive `@Component` becomes a hydration island automatically. The scope is INFERRED
        // from the cells this instance created (the data-leak boundary, computed by the engine — not a
        // hand-written `scope:` allowlist). The cells are known after body-eval, before lowering.
        let scope = context.arena.cells(inScope: context.scope)
        target.islandOpen(id: IslandID("c\(context.scope)"), on: hydration, scope: scope, connect: nil, key: nil)
        Body._render(built, into: &target)
        target.islandClose()
    }
}
