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

    // MARK: - P2: class-merge (ADR-0017)

    /// Toggle the presence of CSS class `name` on this element from a boolean cell, **merging** — it
    /// `classList.toggle`s on the client, never clobbering the static `class` (unlike `bind(.class,)`
    /// which sets `className` wholesale). Emits `data-adh-class="name:cell"`; repeated calls coalesce into
    /// one attribute (`name:cell;name2:cell2`). The `cell`-typed overloads also paint the class into the
    /// initial `class` when the cell is initially on, so there is no hydration flash.
    public consuming func classToggle(_ name: String, when cell: CellID) -> Self {
        attribute("data-adh-class", "\(name):\(cell.raw)")
    }
    /// Toggle `name` from a `Signal<Bool>` (no `.id` ceremony); paints the class initially if the signal is on.
    public consuming func classToggle(_ name: String, when signal: Signal<Bool>) -> Self {
        classToggling(name, cell: signal.id, initiallyOn: signal.stored)
    }
    /// Toggle `name` from a `Computed<Bool>`; paints the class initially if the computed is on.
    public consuming func classToggle(_ name: String, when computed: Computed<Bool>) -> Self {
        classToggling(name, cell: computed.id, initiallyOn: computed.stored)
    }
    /// Toggle `name` from a derived `Reactive<Bool>` (client-recomputable, like `bind(_:to:Reactive)`); a
    /// no-op outside a hydration context (static render). Paints the class initially when the value is true.
    public consuming func classToggle(_ name: String, when reactive: Reactive<Bool>) -> Self {
        guard let context = ADHTMLRenderContext.current else { return self }
        return classToggling(name, cell: context.arena.computed(reactive).id, initiallyOn: reactive.value)
    }
    private consuming func classToggling(_ name: String, cell: CellID, initiallyOn: Bool) -> Self {
        var node = attribute("data-adh-class", "\(name):\(cell.raw)")
        if initiallyOn { node = node.class(name) }  // no-FOUC: the initial server class matches the cell
        return node
    }

    // MARK: - P6: conditional visibility — `.show(when:)` (ADR-0017)

    /// Show/hide this element by toggling `display` from a boolean cell (`data-adh-show`). The element
    /// stays in the DOM (vs `When`, which mounts/unmounts); the `cell`-typed overloads stamp the initial
    /// `display:none` when the cell is initially off, so it is hidden without JS and never flashes.
    public consuming func show(when cell: CellID) -> Self {
        attribute("data-adh-show", "\(cell.raw)")
    }
    /// Show/hide from a `Signal<Bool>`; renders hidden initially (inline `display:none`) when the signal is off.
    public consuming func show(when signal: Signal<Bool>) -> Self {
        showing(cell: signal.id, initiallyVisible: signal.stored)
    }
    /// Show/hide from a `Computed<Bool>`; renders hidden initially when the computed is off.
    public consuming func show(when computed: Computed<Bool>) -> Self {
        showing(cell: computed.id, initiallyVisible: computed.stored)
    }
    /// Show/hide from a derived `Reactive<Bool>`; a no-op outside a hydration context (static render).
    public consuming func show(when reactive: Reactive<Bool>) -> Self {
        guard let context = ADHTMLRenderContext.current else { return self }
        return showing(cell: context.arena.computed(reactive).id, initiallyVisible: reactive.value)
    }
    private consuming func showing(cell: CellID, initiallyVisible: Bool) -> Self {
        var node = attribute("data-adh-show", "\(cell.raw)")
        if !initiallyVisible { node = node.attribute("style", "display:none") }  // hidden without JS, no FOUC
        return node
    }
}

// MARK: - P6: conditional mount/unmount — `When` (ADR-0017)

/// Conditionally MOUNT content from a boolean cell (`v-if`-style, ADR-0017). Lowers to an inert
/// `<template data-adh-if="cell">…</template>`; the runtime clones the template's content into the DOM
/// when the cell is truthy and removes it when falsy. Because the content lives in a `<template>`, it is
/// absent without JS — the correct fallback for the on-demand reveals this serves (a popover, a spinner,
/// a hint, a clear button: all hidden until an interaction flips the cell). For content that must exist
/// without JS and merely toggles visibility, use `.show(when:)` instead (it keeps the node in the DOM).
public struct When<Content: HTML>: HTML {
    @usableFromInline let cell: CellID?
    @usableFromInline let content: Content

    @usableFromInline init(cell: CellID?, content: Content) {
        self.cell = cell
        self.content = content
    }

    /// Mount `content` when `cell` is truthy.
    public init(_ cell: CellID, @HTMLBuilder content: () -> Content) {
        self.init(cell: cell, content: content())
    }
    /// Mount `content` when `signal` is true.
    public init(_ signal: Signal<Bool>, @HTMLBuilder content: () -> Content) {
        self.init(cell: signal.id, content: content())
    }
    /// Mount `content` when `computed` is true.
    public init(_ computed: Computed<Bool>, @HTMLBuilder content: () -> Content) {
        self.init(cell: computed.id, content: content())
    }
    /// Mount `content` when a derived `Reactive<Bool>` is true; registers a client-recomputable cell. With
    /// no hydration context (static render) it has no cell and renders the content inline (degraded, like
    /// `bind(_:to:Reactive)`).
    public init(_ reactive: Reactive<Bool>, @HTMLBuilder content: () -> Content) {
        self.init(cell: ADHTMLRenderContext.current?.arena.computed(reactive).id, content: content())
    }

    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        guard let cell = html.cell else {
            Content._render(html.content, into: &target)  // no context: inline the content (degraded static)
            return
        }
        target.openTagStart("<template")
        target.attribute(name: "data-adh-if", value: "\(cell.raw)", context: .attribute)
        target.openTagEnd()
        Content._render(html.content, into: &target)
        target.closeTag("</template>")
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
