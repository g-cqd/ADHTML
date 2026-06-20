private import Synchronization

// The reactive-cell graph for ONE render (RFC-0003 / ADR-0004). The server renders once, so it does
// not run a propagation loop: it EVALUATES each cell's value for the initial HTML and RECORDS the
// dependency graph (computed → the cells it read) for serialization. The full push-pull reactivity is
// the client runtime's job. Sendable: cells live behind a `Mutex` so a streaming (async) render is
// data-race-free. Dependency capture uses a "currently collecting" slot toggled around a computed's
// body (the body runs OUTSIDE the lock; each read briefly locks to append) — the alien-signals /
// Vue "current computation" idea, single-slot because computeds evaluate eagerly (no nested eval).

/// Owns the reactive-cell graph for one render and records it for hydration serialization.
public final class CellArena: Sendable {
    /// A recorded cell: its id, kind, and current (server-evaluated) value.
    public struct Cell: Sendable, Equatable {
        public let id: CellID
        public let kind: Kind
        public let value: WireValue

        public enum Kind: Sendable, Equatable {
            case signal
            /// A derived cell. `expr` is the client-recomputable formula when built from the `Reactive`
            /// DSL (``CellArena/computed(_:)-(Reactive<Value>)``), else `nil` (server-evaluated closure,
            /// updated by SSE patch).
            case computed(dependencies: [CellID], expr: WireExpr?)
        }
    }

    /// Dedup key for a `@State` cell: the component scope + the property name. A struct (not the former
    /// `"\(scope).\(key)"` string) so a repeated read does not allocate a fresh interpolated String each
    /// time — it hashes the existing `key` literal and the scalar `scope` in place.
    private struct StateKey: Hashable {
        let scope: UInt64
        let key: String
    }

    private struct State {
        var cells: [Cell] = []
        var nextIndex: UInt64 = 0
        /// Non-nil while a computed's body evaluates; reads append their `CellID` here.
        var collecting: [CellID]?
        /// Monotonic per-render component scope counter (see ``freshScope()``).
        var nextScope: UInt64 = 0
        /// `(scope, key)` → the cell backing a `@State` property, so repeated reads dedup (see
        /// ``stateCell(scope:key:default:)``).
        var stateKeys: [StateKey: CellID] = [:]
        /// `scope` → the cells created within it, so an ``InteractiveComponent`` can INFER its island
        /// scope (the cells it owns) instead of the author hand-listing a `scope:` allowlist.
        var scopeCells: [UInt64: [CellID]] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    /// Create a signal seeded with `initial`. The returned handle carries the typed value for
    /// read-back during render; the arena records the cell for serialization.
    public func signal<Value: WireEncodable>(_ initial: Value) -> Signal<Value> {
        let id = register(.signal, value: initial.wireValue)
        return Signal(arena: self, id: id, stored: initial)
    }

    /// Create a computed cell from an opaque closure. `body` is evaluated once now (the server's single
    /// render pass); reads of other cells during it become this cell's recorded dependencies. The client
    /// cannot re-run the closure, so the cell's value is server-fixed (updated by SSE patch).
    public func computed<Value: WireEncodable>(_ body: () -> Value) -> Computed<Value> {
        state.withLock { $0.collecting = [] }
        let result = body()
        let dependencies = state.withLock { lock -> [CellID] in
            let deps = lock.collecting ?? []
            lock.collecting = nil
            return deps
        }
        let id = register(.computed(dependencies: dependencies, expr: nil), value: result.wireValue)
        return Computed(arena: self, id: id, stored: result)
    }

    /// Create a computed cell from a ``Reactive`` expression. Evaluated once now for the initial value
    /// AND serialized as a `WireExpr` (the cell's `e`) so the client re-evaluates it reactively — a
    /// derived cell that updates in-browser with no server round-trip. Its dependencies are the cells the
    /// expression references.
    public func computed<Value: WireEncodable>(_ reactive: Reactive<Value>) -> Computed<Value> {
        let id = register(
            .computed(dependencies: reactive.expr.cellRefs, expr: reactive.expr),
            value: reactive.value.wireValue)
        return Computed(arena: self, id: id, stored: reactive.value)
    }

    /// Record that the currently-evaluating computed (if any) read cell `id`.
    func recordRead(_ id: CellID) {
        state.withLock { if $0.collecting != nil { $0.collecting?.append(id) } }
    }

    /// A fresh per-render component scope id (monotonic within this render). ``Component`` rendering
    /// claims one per instance so two instances of one component type get distinct `@State` cells.
    func freshScope() -> UInt64 {
        state.withLock { lock in
            let scope = lock.nextScope
            lock.nextScope += 1
            return scope
        }
    }

    /// Get-or-create the signal cell backing a `@State` property, keyed by `(scope, key)`. The first
    /// read within a render registers the cell; later reads of the same property return the same handle
    /// (a stable ``CellID``) rather than registering a duplicate — so `@State var count` referenced by
    /// both an event behavior and a binding resolves to ONE cell.
    public func stateCell<Value: WireEncodable>(scope: UInt64, key: String, default defaultValue: Value)
        -> Signal<Value>
    {
        let composite = StateKey(scope: scope, key: key)
        let id = state.withLock { lock -> CellID in
            if let existing = lock.stateKeys[composite] { return existing }
            let id = CellID(lock.nextIndex)
            lock.nextIndex += 1
            lock.cells.append(Cell(id: id, kind: .signal, value: defaultValue.wireValue))
            lock.stateKeys[composite] = id
            lock.scopeCells[scope, default: []].append(id)
            return id
        }
        return Signal(arena: self, id: id, stored: defaultValue)
    }

    /// All recorded cells, in creation order — the wire serializer's input.
    public var cells: [Cell] { state.withLock { $0.cells } }

    /// The cells created within a component's render `scope` — the inferred island scope for an
    /// ``InteractiveComponent`` (the data-leak boundary, computed instead of hand-listed as `scope:`).
    func cells(inScope scope: UInt64) -> [CellID] { state.withLock { $0.scopeCells[scope] ?? [] } }

    private func register(_ kind: Cell.Kind, value: WireValue) -> CellID {
        // Attribute the cell to the component currently rendering (if any), so its island can infer scope.
        let scope = ADHTMLRenderContext.current?.scope
        return state.withLock { lock -> CellID in
            let id = CellID(lock.nextIndex)
            lock.nextIndex += 1
            lock.cells.append(Cell(id: id, kind: kind, value: value))
            if let scope { lock.scopeCells[scope, default: []].append(id) }
            return id
        }
    }
}
