/// A derived reactive cell — a Sendable value-type handle into a ``CellArena``. It is evaluated once
/// during the server's render pass; the cells read during that evaluation are recorded as its
/// dependencies (for the wire graph). Reading ``value`` records a dependency edge (so a downstream
/// ``Computed`` captures it) and returns the evaluated value. Re-derivation on change is the client
/// runtime's job (RFC-0003).
public struct Computed<Value: WireEncodable>: Sendable {
    public let id: CellID
    let arena: CellArena
    let stored: Value

    init(arena: CellArena, id: CellID, stored: Value) {
        self.arena = arena
        self.id = id
        self.stored = stored
    }

    /// The evaluated value. Reading it inside another `CellArena.computed(_:)` records the edge.
    public var value: Value {
        arena.recordRead(id)
        return stored
    }
}
