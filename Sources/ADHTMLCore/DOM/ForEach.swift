// `ForEach` over a sequence (RFC-0020 §1 — the static builder-loop alias) AND over a reactive array
// (RFC-0021 P3 — a CLIENT list). The static form materializes rows eagerly and lowers them like an inline
// `for` (byte-identical). The client form takes a `Signal<[String]>`: it lowers a `<template
// data-adh-each="cell">ROW</template>` (the row STRUCTURE, with `EachText` slots) followed by the initial
// server rows (rendered from the signal's current value — the no-JS fallback). On the client the runtime
// clones the template per array element + reconciles via morph, so the list tracks the signal in-browser.

/// A homogeneous list of rows — over a `Sequence` (static) or a `Signal<[String]>` (client, P3).
public struct ForEach<Row: HTML>: HTML {
    @usableFromInline let rows: [Row]
    /// Client-list mode (P3): the array signal cell; `nil` ⇒ static mode (no template emitted).
    @usableFromInline let eachCell: CellID?
    /// An optional `data-adh-filter` query cell — rows whose text contains the query render (client-side).
    @usableFromInline let filterCell: CellID?
    /// The placeholder row (`EachText` slots empty) cloned per element on the client; `nil` in static mode.
    @usableFromInline let templateRow: Row?

    @usableFromInline
    init(rows: [Row], eachCell: CellID?, filterCell: CellID?, templateRow: Row?) {
        self.rows = rows
        self.eachCell = eachCell
        self.filterCell = filterCell
        self.templateRow = templateRow
    }

    /// Build one `Row` per element of `data` (eager static loop, matching `_HTMLArray`).
    @inlinable
    public init<Data: Sequence>(_ data: Data, @HTMLBuilder _ row: (Data.Element) -> Row) {
        self.init(rows: data.map(row), eachCell: nil, filterCell: nil, templateRow: nil)
    }

    /// A CLIENT list over an array signal (P3): the row references the current element via `item.text`.
    /// `filteredBy` renders only rows whose text contains the query (client-side, case-insensitive). The
    /// initial rows render from the signal's current value (no-JS); the runtime reconciles on change.
    public init(
        _ items: Signal<[String]>,
        filteredBy filter: Signal<String>? = nil,
        @HTMLBuilder row: (EachItem) -> Row
    ) {
        self.init(
            rows: items.stored.map { row(EachItem(value: $0)) },
            eachCell: items.id,
            filterCell: filter?.id,
            templateRow: row(EachItem(value: nil)))
    }

    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        if let eachCell = html.eachCell {  // client mode: emit the row template before the initial rows
            target.openTagStart("<template")
            target.attribute(name: "data-adh-each", value: "\(eachCell.raw)", context: .attribute)
            if let filterCell = html.filterCell {
                target.attribute(name: "data-adh-filter", value: "\(filterCell.raw)", context: .attribute)
            }
            target.openTagEnd()
            if let templateRow = html.templateRow { Row._render(templateRow, into: &target) }
            target.closeTag("</template>")
        }
        for row in html.rows { Row._render(row, into: &target) }  // iterative; no recursion over the tree
    }
}

/// The current element handed to a client `ForEach`'s row builder. In the template pass `value` is `nil`
/// (the slots render empty); in each server row it is the element (the slots render its escaped text).
public struct EachItem: Sendable {
    @usableFromInline let value: String?
    @usableFromInline init(value: String?) { self.value = value }

    /// The element's text in a runtime-fillable slot (`<span data-adh-each-text>`): empty in the template,
    /// the escaped element in each server row. The runtime sets `textContent` per clone.
    public var text: EachText { EachText(value: value) }
}

/// A client-list text slot (`<span data-adh-each-text>`) — empty in the row template, the escaped element
/// in a server row. The P3 runtime fills its `textContent` per cloned element.
public struct EachText: HTML {
    @usableFromInline let value: String?
    @usableFromInline init(value: String?) { self.value = value }

    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        target.openTagStart("<span")
        target.attribute(name: "data-adh-each-text", value: "", context: .attribute)
        target.openTagEnd()
        if let value = html.value { target.text(value) }
        target.closeTag("</span>")
    }
}
