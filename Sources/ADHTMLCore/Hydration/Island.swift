/// An opt-in interactive region (ADR-0005). The static perimeter is plain server HTML with zero JS;
/// an island is wired by the client runtime per its ``LoadStrategy``. `scope` lists the seed cells
/// this island owns — the wire serializer walks their dependencies and serializes **only** the
/// reachable cells (the data-leak guard, RFC-0003 §6). Lowers to `islandOpen`/`islandClose` opcodes.
public struct Island<Content: HTML>: HTML {
    public let id: IslandID
    public let on: LoadStrategy
    public let scope: [CellID]
    public let connect: String?
    public let content: Content

    public init(
        _ id: IslandID,
        on: LoadStrategy = .load,
        scope: [CellID] = [],
        connect: String? = nil,
        @HTMLBuilder content: () -> Content
    ) {
        self.id = id
        self.on = on
        self.scope = scope
        self.connect = connect
        self.content = content()
    }

    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        target.islandOpen(id: html.id, on: html.on, scope: html.scope, connect: html.connect)
        Content._render(html.content, into: &target)
        target.islandClose()
    }
}
