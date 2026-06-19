/// A stable identifier for a hydration island, emitted as `data-adh-id`. Author-provided (readable for
/// debugging); the runtime uses it to scope event delegation and SSE morph/patch targeting (RFC-0003).
public struct IslandID: Hashable, Sendable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public var description: String { raw }
}

extension IslandID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.raw = value }
}
