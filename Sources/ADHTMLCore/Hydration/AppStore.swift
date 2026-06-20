// `AppStore` — a document-level reactive store (RFC-0021 P8, unblocks the prototype's S1/L2/S3/X3 persisted
// UI state: theme, sidebar-open, a cross-page filter). Its signals are created at the page root and SURVIVE
// boosted navigations: a `Link.boost` (P7) morphs a nested ``Region``, never this root island or the inline
// `#adh-state` script, so the store's cells + their bindings persist across SPA-feel navigations while only
// the morphed region's own cells reset. It is a thin, stably-keyed root ``Island`` that hands its body a
// ``StoreScope`` for declaring named, persistent signals.
//
// Scope: bind store signals in the page chrome (OUTSIDE boosted regions) — those bindings are never morphed,
// so they keep tracking the store across navigations. A store binding placed *inside* a boosted region is
// re-rendered by the server with the correct initial value on each navigation (no flash), but the runtime
// does not re-wire morphed-in nodes, so it stops updating reactively until the next full load — keep
// reactive store-driven UI in the persistent chrome.

/// The reserved `id` of the document-level store island — stable across re-renders (one store per app, like
/// a single SwiftUI environment), so a boosted navigation can never accidentally target it as a morph anchor.
private let storeID = IslandID("adh-store")

/// Hands an ``AppStore`` body its document-level signals. Each ``signal(_:default:)`` is keyed by name and
/// **deduped** — reading the same key twice returns the same cell — so a store value referenced by several
/// views resolves to ONE persistent cell.
public struct StoreScope: Sendable {
    @usableFromInline let arena: CellArena?
    @usableFromInline let scope: UInt64
    @usableFromInline init(arena: CellArena?, scope: UInt64) {
        self.arena = arena
        self.scope = scope
    }

    /// A persistent, document-level signal named `key`, seeded with `value`. Repeated reads of the same key
    /// return the same cell (deduped). Survives boosted navigations. Outside a hydration context (a static
    /// render) it returns a throwaway handle so the view still renders, just without persistence wiring.
    public func signal<Value: WireEncodable>(_ key: String, default value: Value) -> Signal<Value> {
        (arena ?? CellArena()).stateCell(scope: scope, key: key, default: value)
    }
}

/// A document-level reactive store whose signals survive boosted (`Link.boost`) navigations (RFC-0021 P8).
/// Wrap the page body in it and declare persistent state through the ``StoreScope`` handed to the builder:
///
/// ```swift
/// AppStore { store in
///     let dark = store.signal("dark", default: false)
///     body.classToggle("dark", when: dark)   // bound in the chrome -> persists across boosts
/// }
/// ```
public struct AppStore<Content: HTML>: HTML {
    @usableFromInline let build: @Sendable (StoreScope) -> Content

    /// Build the page body with access to document-level persistent signals.
    public init(@HTMLBuilder _ build: @escaping @Sendable (StoreScope) -> Content) {
        self.build = build
    }

    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        // Static / no-JS render (no ambient context): build with a throwaway scope, no island, no wiring.
        guard let context = ADHTMLRenderContext.child() else {
            Content._render(html.build(StoreScope(arena: nil, scope: 0)), into: &target)
            return
        }
        // Interactive: the store signals register in this island's scope; bind them in the chrome to persist.
        ADHTMLRenderContext.$current.withValue(context) {
            let content = html.build(StoreScope(arena: context.arena, scope: context.scope))
            let scope = context.arena.cells(inScope: context.scope)
            target.islandOpen(id: storeID, on: .load, scope: scope, connect: nil, key: nil)
            Content._render(content, into: &target)
            target.islandClose()
        }
    }
}
