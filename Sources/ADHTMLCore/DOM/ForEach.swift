// RFC-0020 Tier-1 §1: `ForEach(data) { row }` — the explicit, SwiftUI-shaped form of a `for` loop in an
// `@HTMLBuilder` block. It materializes its rows eagerly (exactly like the builder's `_HTMLArray`) and
// lowers them with the same iterative, non-recursive loop, so it is byte-identical to writing the `for`
// inline — just clearer at the call site. Keyed-row support (stamping `id=` per row for morph-stable
// reorders) is a follow-up; today a row that needs a stable key sets its own `.id(...)`.

/// A homogeneous sequence of views built from `data`. Equivalent to a `for` in a builder block.
public struct ForEach<Row: HTML>: HTML {
    @usableFromInline let rows: [Row]

    /// Build one `Row` per element of `data` (eager, matching `_HTMLArray`).
    @inlinable
    public init<Data: Sequence>(_ data: Data, @HTMLBuilder _ row: (Data.Element) -> Row) {
        self.rows = data.map(row)
    }

    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        for row in html.rows { Row._render(row, into: &target) }  // iterative; no recursion over the tree
    }
}
