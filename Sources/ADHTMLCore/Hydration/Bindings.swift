// Element-level hydration bindings (ADR-0005/0007). Bindings live as `data-adh-*` attributes in the
// rendered HTML; the client runtime reads them from the DOM (Datastar/htmx model), so the inline wire
// payload only carries the cell graph + island scope, never the bindings (smaller, no duplication).

/// What a value binding drives on its element.
public enum BindTarget: String, Sendable, Equatable {
    case text
    case value
    case `class`
}

extension HTMLElement {
    /// Wire a client behavior to a DOM event — emits `data-adh-on:<event>="<behavior>#<cell>[#param…]"`.
    public consuming func on(_ event: String, _ invocation: BehaviorInvocation) -> Self {
        attribute("data-adh-on:\(event)", invocation.attributeValue)
    }

    /// Bind a reactive cell to this element's text/value/class — emits `data-adh-bind:<target>="<cell>"`.
    public consuming func bind(_ target: BindTarget, to cell: CellID) -> Self {
        attribute("data-adh-bind:\(target.rawValue)", "\(cell.raw)")
    }
}
