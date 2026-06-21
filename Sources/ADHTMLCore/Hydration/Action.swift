// A typed, Swift-authored client action (RFC-0019 §3.1/§6.3-F). An `Action` is a client-issued request
// bound to a DOM event, whose `text/html` response is applied to a target region. It lowers to a closed
// set of `data-adh-*` attributes (the shared wire, contract C3) that the runtime's delegated listener
// interprets — the JS side is `action.js`, and `Action.methods` ↔ `ACTION_METHODS` are kept in sync by a
// parity test, exactly like `Behavior` ↔ `behaviors.js`. The verb set is CLOSED (get/post/put/patch/
// delete) so the runtime stays a tiny generic interpreter and illegal verbs can't be authored.
//
// This is the realization of ADR-0044/0048's deferred "first-party client-action DSL" — htmx's
// capability with ADHTML's ergonomics (Swift-typed, one wire format), not an untyped attribute soup.
// Static fallback is preserved by construction: without the runtime the element still behaves natively
// (an input inside a `<form>` submits), so every action degrades to a server round-trip.

/// How an ``Action``'s response HTML is applied to its target region (contract C3, mirrors `action.js`).
public enum Swap: String, Sendable, Equatable {
    /// Reconcile the target's subtree to the response (idiomorph-style; preserves focus/selection). Default.
    case morph
    /// Replace the target's `innerHTML` wholesale.
    case innerHTML
    /// Append the response to the end of the target.
    case append
    /// The response carries its own `x`(oob)-tagged regions; the runtime morphs each by id.
    case outOfBand

    /// The wire token for this swap mode (generated `WireSwap`; mirrored by `S` in `action.js`).
    var token: String {
        switch self {
            case .morph: WireSwap.morph
            case .innerHTML: WireSwap.innerHTML
            case .append: WireSwap.append
            case .outOfBand: WireSwap.outOfBand
        }
    }
}

/// A client-issued request bound to a DOM event, whose response updates a region. Built by a verb factory
/// (`.get`/`.post`/…) then refined with chainable modifiers (each returns a copy). Apply it to an element
/// with `.action(_:)`.
public struct Action: Sendable, Equatable {
    /// The HTTP verb, lowercased — emitted as `data-adh-action`. One of ``Action/methods``.
    public let method: String
    /// The request path — emitted as `data-adh-url`.
    public let path: String
    /// The DOM event that fires the action; `nil` lets the runtime default (submit for a `<form>`, else click).
    public var trigger: DOMEvent?
    /// Coalescing delay before firing (e.g. search-as-you-type); `nil` fires immediately.
    public var debounce: Duration?
    /// Extra named fields to serialize alongside the enclosing form / the element's own value.
    public var includes: [String]
    /// The region to update; `nil` lets the runtime default to the enclosing island.
    public var targetID: IslandID?
    /// How the response is applied. Defaults to ``Swap/morph``.
    public var swap: Swap
    /// A client behavior applied to a cell *before* the fetch — an instant, optimistic UI update.
    public var optimistic: BehaviorInvocation?

    private init(method: String, path: String) {
        self.method = method
        self.path = path
        self.includes = []
        self.swap = .morph
    }

    /// The closed verb set, mirrored by `ACTION_METHODS` in `action.js` (parity test).
    public static let methods = ["get", "post", "put", "patch", "delete"]

    /// `GET path` — serializes inputs into the query string.
    public static func get(_ path: String) -> Action { Action(method: "get", path: path) }
    /// `POST path` — serializes the enclosing `<form>` into the request body.
    public static func post(_ path: String) -> Action { Action(method: "post", path: path) }
    /// `PUT path`.
    public static func put(_ path: String) -> Action { Action(method: "put", path: path) }
    /// `PATCH path`.
    public static func patch(_ path: String) -> Action { Action(method: "patch", path: path) }
    /// `DELETE path`.
    public static func delete(_ path: String) -> Action { Action(method: "delete", path: path) }

    /// The DOM event that fires the action (default: submit for forms, click otherwise).
    public func trigger(_ event: DOMEvent) -> Action {
        var copy = self
        copy.trigger = event
        return copy
    }
    /// Coalesce rapid triggers to one request after `duration` of quiet (e.g. `.milliseconds(200)`).
    public func debounce(_ duration: Duration) -> Action {
        var copy = self
        copy.debounce = duration
        return copy
    }
    /// Also serialize these named fields (resolved from the document) with the request.
    public func include(_ fields: String...) -> Action {
        var copy = self
        copy.includes += fields
        return copy
    }
    /// The region to update (default: the enclosing island).
    public func target(_ id: IslandID) -> Action {
        var copy = self
        copy.targetID = id
        return copy
    }
    /// How to apply the response (default: ``Swap/morph``).
    public func swap(_ mode: Swap) -> Action {
        var copy = self
        copy.swap = mode
        return copy
    }
    /// Apply a client behavior instantly, before the request resolves (the server fragment then reconciles).
    public func optimistic(_ behavior: BehaviorInvocation) -> Action {
        var copy = self
        copy.optimistic = behavior
        return copy
    }

    /// The debounce as whole milliseconds — the `data-adh-debounce` unit — or `nil` when unset.
    var debounceMilliseconds: Int? {
        guard let debounce else { return nil }
        let components = debounce.components
        return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}

extension HTMLElement {
    /// Bind a client ``Action`` to this element — emits the `data-adh-*` attribute set (contract C3):
    /// `data-adh-action`/`data-adh-url` plus whichever modifiers are set (`-trigger`, `-debounce`,
    /// `-include`, `-target`, `-swap`, `-optimistic`). The runtime fetches with the `ADH-Request: 1`
    /// header (C1) and applies the `text/html` response (C2) per ``Action/swap``.
    public consuming func action(_ action: Action) -> Self {
        var node = attribute(WireToken.action, action.method)
        node = node.attribute(WireToken.url, action.path)
        if let trigger = action.trigger {
            node = node.attribute(WireToken.trigger, trigger.name)
        }
        if let milliseconds = action.debounceMilliseconds {
            node = node.attribute(WireToken.debounce, String(milliseconds))
        }
        if !action.includes.isEmpty {
            node = node.attribute(WireToken.include, action.includes.joined(separator: ","))
        }
        if let targetID = action.targetID {
            node = node.attribute(WireToken.target, targetID.raw)
        }
        node = node.attribute(WireToken.swap, action.swap.token)
        if let optimistic = action.optimistic {
            node = node.attribute(WireToken.optimistic, optimistic.attributeValue)
        }
        return node
    }
}
