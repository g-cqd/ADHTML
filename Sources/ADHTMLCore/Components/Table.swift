// A generic, type-preserved data table — the rich member of the component vocabulary. Columns are declared
// inline with a result builder; each column KEEPS ITS OWN cell type via a parameter pack (variadic
// generics), so one table freely mixes links, pills, token-fields with NO type erasure and no existentials
// in the render path. App-agnostic: it knows nothing about any specific row model.

/// One column of a ``Table``: a header plus a cell builder over the row. The cell type is preserved per
/// column (it is a pack element), so different columns render different `some HTML`.
public struct Column<Row, Cell: HTML>: Sendable {
    public let header: String
    public let cell: @Sendable (Row) -> Cell

    public init(_ header: String, @HTMLBuilder _ cell: @escaping @Sendable (Row) -> Cell) {
        self.header = header
        self.cell = cell
    }
}

/// Collects a table's columns, preserving each column's distinct cell type as a parameter pack.
@resultBuilder
public enum ColumnBuilder {
    public static func buildBlock<Row, each Cell: HTML>(
        _ columns: repeat Column<Row, each Cell>
    ) -> (repeat Column<Row, each Cell>) {
        (repeat each columns)
    }
}

/// A semantic data table over `rows` with columns declared inline:
///
/// ```swift
/// Table(parts) {
///     Column("Spare part") { (part: Part) in a { part.name }.href("/parts/\(part.id)") }
///     Column("Status")     { (part: Part) in Pill(part.status, tone: .positive) }
/// }
/// ```
///
/// Each column keeps its own cell type, so a table mixes rich cells (links, ``Pill``s, even a ``TokenField``)
/// with no type erasure. Renders accessible `<table><thead><tbody>` markup; the consumer supplies the CSS.
///
/// > Note: annotate the column closure's row parameter (`{ (part: Part) in … }`). Swift can't yet infer it
/// > through the column parameter pack + result builder from `rows` alone — the one cost of the no-erasure
/// > design (an existential-based table would infer it but reintroduce the erasure this avoids).
public struct Table<Row: Sendable, each Cell: HTML>: HTML {
    public let rows: [Row]
    public let columns: (repeat Column<Row, each Cell>)

    public init(_ rows: [Row], @ColumnBuilder columns: () -> (repeat Column<Row, each Cell>)) {
        self.rows = rows
        self.columns = columns()
    }

    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        target.openTagStart("<table")
        target.attribute(name: "class", value: "table", context: .attribute)
        target.openTagEnd()

        target.openTagStart("<thead")
        target.openTagEnd()
        target.openTagStart("<tr")
        target.openTagEnd()
        for column in repeat each html.columns {
            target.openTagStart("<th")
            target.openTagEnd()
            target.text(column.header)
            target.closeTag("</th>")
        }
        target.closeTag("</tr>")
        target.closeTag("</thead>")

        target.openTagStart("<tbody")
        target.openTagEnd()
        for row in html.rows {
            target.openTagStart("<tr")
            target.openTagEnd()
            for column in repeat each html.columns {
                target.openTagStart("<td")
                target.openTagEnd()
                Self.lower(column.cell(row), into: &target)
                target.closeTag("</td>")
            }
            target.closeTag("</tr>")
        }
        target.closeTag("</tbody>")
        target.closeTag("</table>")
    }

    @inline(__always)
    private static func lower<V: HTML, Target: RenderTarget>(_ view: V, into target: inout Target) {
        V._render(view, into: &target)
    }
}
