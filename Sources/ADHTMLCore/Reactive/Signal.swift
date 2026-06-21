/// A reactive state cell — a Sendable value-type handle into a ``CellArena``. Reading ``value``
/// records a dependency on the active computation (so a ``Computed`` that reads it captures the edge)
/// and returns the server-evaluated value. On the server a signal is created once with its initial
/// value; mutation and propagation happen in the client runtime (RFC-0003).
public struct Signal<Value: WireEncodable>: Sendable {
    public let id: CellID
    let arena: CellArena
    let stored: Value

    init(arena: CellArena, id: CellID, stored: Value) {
        self.arena = arena
        self.id = id
        self.stored = stored
    }

    /// The current value. Reading it inside `CellArena.computed(_:)` records the dependency edge.
    public var value: Value {
        arena.recordRead(id)
        return stored
    }
}
