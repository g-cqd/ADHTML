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

    /// Bind a `Signal` directly (no `.id` ceremony).
    public consuming func bind<Value: WireEncodable>(_ target: BindTarget, to signal: Signal<Value>) -> Self {
        bind(target, to: signal.id)
    }

    /// Bind a `Computed` directly.
    public consuming func bind<Value: WireEncodable>(_ target: BindTarget, to computed: Computed<Value>)
        -> Self
    {
        bind(target, to: computed.id)
    }

    /// Bind a derived `Reactive` expression — a plain computed property like
    /// `var total: Reactive<Int> { $a.reactive + $b.reactive }`. Registers it as a client-recomputable
    /// computed cell in the ambient arena (so it updates in-browser) and binds to it. A no-op in a static
    /// render (no ambient context).
    public consuming func bind<Value: WireEncodable>(_ target: BindTarget, to reactive: Reactive<Value>)
        -> Self
    {
        guard let context = ADHTMLRenderContext.current else { return self }
        return bind(target, to: context.arena.computed(reactive).id)
    }

    /// Wire a client behavior to a typed DOM event — `.on(.click, …)`.
    public consuming func on(_ event: DOMEvent, _ invocation: BehaviorInvocation) -> Self {
        on(event.name, invocation)
    }
}

/// A delegated DOM event. The runtime registers one document-level listener per event type it knows
/// (qwikloader-style). The cases mirror the runtime's delegated set (a parity test keeps them in sync);
/// `.custom` carries any other type, which fires only if the runtime delegates it.
public enum DOMEvent: Sendable, Equatable {
    case click, dblclick, input, change
    case keydown, keyup, keypress
    case focusIn, focusOut
    case pointerdown, pointerup
    case mousedown, mouseup, mouseover, mouseout
    case contextmenu
    case custom(String)

    /// The event name as written into `data-adh-on:<name>`.
    public var name: String {
        switch self {
            case .click: "click"
            case .dblclick: "dblclick"
            case .input: "input"
            case .change: "change"
            case .keydown: "keydown"
            case .keyup: "keyup"
            case .keypress: "keypress"
            case .focusIn: "focusin"
            case .focusOut: "focusout"
            case .pointerdown: "pointerdown"
            case .pointerup: "pointerup"
            case .mousedown: "mousedown"
            case .mouseup: "mouseup"
            case .mouseover: "mouseover"
            case .mouseout: "mouseout"
            case .contextmenu: "contextmenu"
            case .custom(let name): name
        }
    }

    /// The closed delegated set the runtime listens for (mirrors `DELEGATED_EVENTS` in runtime.js).
    public static let delegated: [String] = [
        "click", "dblclick", "input", "change", "keydown", "keyup", "keypress", "focusin", "focusout",
        "pointerdown", "pointerup", "mousedown", "mouseup", "mouseover", "mouseout", "contextmenu"
    ]
}
