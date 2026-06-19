/// A stable identifier for a reactive cell. In Phase 1 it is the cell's creation index within its
/// ``CellArena`` (deterministic across identical renders, which is enough for serialization). A later
/// refinement derives it from the render-scope path via `ADFCore.XXH64`, giving stability under
/// structural reordering — required once SSE morph/patch targets cells across renders (RFC-0003).
public struct CellID: Hashable, Sendable, CustomStringConvertible {
    public let raw: UInt64
    @inlinable public init(_ raw: UInt64) { self.raw = raw }
    public var description: String { "#\(raw)" }
}
