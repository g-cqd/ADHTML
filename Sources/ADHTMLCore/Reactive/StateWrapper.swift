private import Synchronization

// `@State` is a property wrapper (RFC-0005 §3.4): the SwiftUI-style projection. `count` is the value (the
// server-render default); `$count` is the ``Signal`` handle that bindings, behaviors, and `@Bound`
// expressions target. The signal resolves against the ambient render arena on first projection and is
// deduped per render through a small reference box — so `$count` read in three places is ONE cell.

/// Component-local reactive state. `@State var count = 0` keeps `count` as the server default and exposes
/// `$count` (the projected ``Signal``). Mutation + propagation are the client runtime's job (RFC-0003); the
/// server creates the cell once with the initial value.
@propertyWrapper
public struct State<Value: WireEncodable>: Sendable {
    /// The server-render default (also the parent-supplied seed via the memberwise `init(wrappedValue:)`).
    public var wrappedValue: Value
    private let cell: StateCell<Value>

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
        self.cell = StateCell()
    }

    /// The reactive handle — `$count`. Resolves (and dedups per render) the cell backing this state.
    public var projectedValue: Signal<Value> {
        cell.resolve(default: wrappedValue)
    }
}

/// A per-`@State` reference box that resolves the backing ``Signal`` once per render and caches it, so every
/// `$state` read in a render shares one cell. Re-resolves when the ambient arena changes (a new render), so a
/// reused component value still wires correctly. `Mutex`-guarded so ``State`` stays `Sendable`.
private final class StateCell<Value: WireEncodable>: Sendable {
    private let slot = Mutex<Signal<Value>?>(nil)

    func resolve(default value: Value) -> Signal<Value> {
        slot.withLock { current in
            // Outside a hydratable render there is no ambient arena: use a throwaway one so the projection
            // still yields a value (no wiring) — the static-render fallback, like the rest of the reactive
            // surface.
            let arena = ADHTMLRenderContext.current?.arena ?? CellArena()
            if let signal = current, signal.arena === arena { return signal }
            let signal = arena.signal(value)
            current = signal
            return signal
        }
    }
}
