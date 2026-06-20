// The ambient reactive context for one render (RFC-0003 / ADR-0004). `@State` reads resolve their cell
// through this — which ``CellArena`` to register in, and the per-instance `scope` that keys the cell —
// so a component author never threads an arena by hand. It is `nil` during a plain `render()` /
// `renderBytes()` (a pure static render does no reactive bookkeeping and pays zero overhead);
// `renderHydratable(arena:)` installs it, and every ``Component`` render pushes a fresh `scope` so that
// multiple instances of one component type get distinct cells. Carried by `@TaskLocal`, so it restores
// automatically at scope exit and is data-race-free across a streaming (async) render.

/// The ambient arena + per-instance scope that `@State` resolves against during a render.
public enum ADHTMLRenderContext {
    /// The active context, or `nil` during a non-hydratable (static) render.
    @TaskLocal public static var current: Context?

    /// An arena to register reactive cells in, plus the scope id of the component currently rendering, plus
    /// the optional component-scoped-asset sink (Track 4; `nil` on the static render path).
    public struct Context: Sendable {
        public let arena: CellArena
        public let scope: UInt64
        public let assets: AssetSink?

        public init(arena: CellArena, scope: UInt64, assets: AssetSink? = nil) {
            self.arena = arena
            self.scope = scope
            self.assets = assets
        }
    }

    /// Resolve a `@State var name = default` declaration to its signal handle. Within an active context
    /// it registers (or returns the already-registered) cell keyed by `(scope, key)`; outside one — a
    /// static render — it returns a throwaway handle so the component still renders, just without
    /// hydration wiring. The generated `@State` accessor is the only caller.
    public static func state<Value: WireEncodable>(key: String, default defaultValue: Value)
        -> Signal<Value>
    {
        if let context = current {
            return context.arena.stateCell(scope: context.scope, key: key, default: defaultValue)
        }
        return CellArena().stateCell(scope: 0, key: key, default: defaultValue)
    }

    /// Resolve a `@Bound var x: Reactive<V> { … }` declaration to its registered computed handle. Within an
    /// active context it registers the `Reactive` expression as a client-recomputable computed cell (the
    /// `Reactive`→`WireExpr`→`Computed` path, so the browser re-evaluates it with no round-trip); outside one
    /// — a static render — a throwaway arena evaluates the value inline with no wiring. The generated
    /// `@Bound` handle (`<name>Computed`) is the only caller.
    public static func bound<Value: WireEncodable>(_ reactive: Reactive<Value>) -> Computed<Value> {
        (current?.arena ?? CellArena()).computed(reactive)
    }

    /// The child context for a nested ``Component`` render: the same arena, a fresh per-instance scope.
    /// `nil` when there is no active context, so a pure static render stays allocation-free.
    static func child() -> Context? {
        guard let parent = current else { return nil }
        return Context(arena: parent.arena, scope: parent.arena.freshScope(), assets: parent.assets)
    }
}
