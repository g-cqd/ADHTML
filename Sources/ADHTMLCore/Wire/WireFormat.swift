/// A hydration island as serialized to the wire (RFC-0003 / ADR-0007): its id, loading strategy, and
/// the **seed** cells whose dependency-closure is serialized. Only cells reachable from some island's
/// scope reach the client — the data-leak guard.
public struct WireIsland: Sendable, Equatable {
    public let id: IslandID
    public let on: LoadStrategy
    public let scope: [CellID]

    public init(id: IslandID, on: LoadStrategy, scope: [CellID]) {
        self.id = id
        self.on = on
        self.scope = scope
    }
}

/// An error from wire serialization.
public enum WireError: Error, Sendable, Equatable {
    case encoding(String)
}
