// The two-protocol model (RFC-0002): `HTML` is the base — every node knows how to lower itself onto
// the flat opcode program. `Component` refines it with a `@HTMLBuilder var body`, exactly the
// SwiftUI `View`/`@ViewBuilder` pattern, so user views compose without ever touching the renderer.
// Lowering is the only protocol requirement; the *render walk* over the produced program is iterative
// (no recursion over a value tree) — see `Renderer`.

/// A node that can lower itself into an ``HTMLProgram``. Conformers are `Sendable` value types; the
/// lowering is static (monomorphized, zero `any`). Primitive nodes implement `_render(_:into:)`
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
    /// Set `true` by `@Component` when the type has `@State`/`@Bound`: the component then AUTO-WRAPS as a
    /// hydration island with an INFERRED scope, so the author writes no `Island`/`scope`/`.id`
    /// (RFC-0005 §3.0). Default `false` — a static component (and a manual `: Component` conformance)
    /// renders inline; an explicit `Island` in the body still works.
    static var isIsland: Bool { get }
    /// When the client runtime wires this component's island (only when `isIsland`). Default `.load`;
    /// override with `static var hydration: LoadStrategy { .visible }` for lazy wiring.
    static var hydration: LoadStrategy { get }
    /// Co-located component-scoped CSS (Track 4) — an additive escape hatch for a bespoke widget. Default
    /// `nil` (no asset). When set, the engine scopes + dedups the CSS, stamps a `data-component`/`data-scope`
    /// mount root, and `renderHydratable` injects one deduped `<style>` before the inline state script.
    static var style: ScopedStyle? { get }
    /// Co-located component-scoped JavaScript (Track 4) — `.inline`/`.module`. Default `nil`. When set, the
    /// engine stamps the `data-component` mount root (so the client `mount` bridge dispatches to the widget's
    /// `ADH.mount(name, fn)`) and injects/serves the script. The widget's only network primitive is the
    /// signed RFC-0019 endpoint; the `body` stays the no-JS fallback.
    static var script: Script? { get }
}

extension Component {
    public static var isIsland: Bool { false }
    public static var hydration: LoadStrategy { .load }
    public static var style: ScopedStyle? { nil }
    public static var script: Script? { nil }

    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        // Pure static render (no hydration): render the body directly — zero reactive bookkeeping.
        guard let base = ADHTMLRenderContext.child() else {
            Body._render(html.body, into: &target)
            return
        }
        // Reactive render: push a fresh per-instance scope so this instance's `@State` cells are
        // distinct from any sibling's. `body` is evaluated INSIDE the scope (where `@State`/computed
        // reads register their cells); lowering the built value afterwards needs no context. An island
        // additionally becomes the OWNERSHIP boundary for cells created in its subtree — so a `@State` /
        // `.show` / computed in a non-island helper nested here is serialized by this island instead of
        // leaking out (the reason a declarative nested widget needs no hand-written hydration script).
        let context = isIsland ? base.asIsland() : base
        // Evaluate the body AND lower it INSIDE this context, so a nested non-island helper component's
        // `_render` inherits `islandScope` — its reactive cells are owned by THIS island instead of leaking
        // out of every scope. (The body was previously lowered outside the context, which is why a `@State`
        // in a nested plain `Component` was silently dropped and forced a hand-written hydration script.)
        ADHTMLRenderContext.$current.withValue(context) {
            let built = html.body

            // Component-scoped assets (Track 4): record this type's style into the ambient sink (deduped)
            // and stamp a `data-component`/`data-scope` mount root. Only when a sink is present.
            var mountRoot: (name: String, scope: String)?
            if Self.style != nil || Self.script != nil, let sink = context.assets {
                let name = String(describing: Self.self)
                let scope = ComponentAssets.record(
                    style: Self.style, script: Self.script, typeName: name, into: sink)
                mountRoot = (name, scope)
            }
            if let mountRoot {
                target.openTagStart("<div")
                target.attribute(name: WireToken.component, value: mountRoot.name, context: .attribute)
                target.attribute(name: WireToken.scope, value: mountRoot.scope, context: .attribute)
                target.openTagEnd()
            }

            if isIsland {
                // An interactive `@Component` auto-wraps as an island. The seed `scope` snapshot here is the
                // cells known BEFORE lowering; the hydration scan re-derives the island's full scope from the
                // arena AFTER lowering (so it includes cells created by nested non-island helpers).
                target.islandOpen(
                    id: IslandID("c\(context.scope)"), on: hydration,
                    scope: context.arena.cells(inScope: context.scope), connect: nil, key: nil)
                Body._render(built, into: &target)
                target.islandClose()
            } else {
                Body._render(built, into: &target)
            }

            if mountRoot != nil { target.closeTag("</div>") }
        }
    }
}
