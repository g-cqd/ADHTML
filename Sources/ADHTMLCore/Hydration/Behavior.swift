// The client-behavior vocabulary (ADR-0005/0009). Authoring goes through the typed factories on
// `Behavior`, which enforce the signal's value type at the call site (`.increment` requires a
// `Signal<Int>`, `.toggle` a `Signal<Bool>`), and produce a uniform `BehaviorInvocation` for the
// wire. The set is CLOSED: the runtime interprets the same fixed set of behavior names (a parity test
// keeps Swift and JS in sync). This is how event→state bindings stay statically checked while the
// client runtime stays a small generic interpreter.

/// A resolved client-behavior reference: a behavior name + the target cell + scalar params, encoded
/// into a `data-adh-on:<event>` attribute as `"<name>#<cell>[#param…]"`.
public struct BehaviorInvocation: Sendable, Equatable {
    public let name: String
    public let cell: CellID
    public let params: [WireValue]

    public init(name: String, cell: CellID, params: [WireValue] = []) {
        self.name = name
        self.cell = cell
        self.params = params
    }

    /// The `data-adh-on:<event>` attribute value.
    public var attributeValue: String {
        var value = "\(name)#\(cell.raw)"
        for param in params { value += "#" + param.scalarToken }
        return value
    }
}

/// The closed set of client behaviors. Each factory is type-checked against the signal it targets.
public enum Behavior {
    /// The closed behavior-token set (the generated `WireBehavior` tokens, in order), mirrored by
    /// `BEHAVIOR_NAMES` in `behaviors.js` (parity test) — the runtime interprets exactly these.
    public static let names = WireBehavior.all.map(\.token)

    /// Set `signal` to a constant value.
    public static func set<Value: WireEncodable>(_ signal: Signal<Value>, to value: Value)
        -> BehaviorInvocation
    {
        BehaviorInvocation(name: WireBehavior.set, cell: signal.id, params: [value.wireValue])
    }

    /// Toggle a boolean signal.
    public static func toggle(_ signal: Signal<Bool>) -> BehaviorInvocation {
        BehaviorInvocation(name: WireBehavior.toggle, cell: signal.id)
    }

    /// Add `step` to an integer signal.
    public static func increment(_ signal: Signal<Int>, by step: Int = 1) -> BehaviorInvocation {
        BehaviorInvocation(name: WireBehavior.increment, cell: signal.id, params: [.int(Int64(step))])
    }

    // MARK: - P4: the extended behavior vocabulary (ADR-0018). Still a CLOSED set, parity-tested.

    /// Set a string signal from the **triggering element's** `value` — e.g. commit an input's text to a
    /// query signal on a key event. The client reads `event.target.value`.
    public static func setFromValue(_ signal: Signal<String>) -> BehaviorInvocation {
        BehaviorInvocation(name: WireBehavior.setFromValue, cell: signal.id)
    }

    /// Move an index signal by `delta`, bounded by the live length in `count` (a `Signal`/`Computed<Int>`
    /// cell — e.g. a filtered list's `count`). Clamps to `[0, count)` by default, or wraps. The keyboard
    /// list-navigation primitive (T5): `ArrowDown` → `listMove(.., by: 1, ..)`.
    public static func listMove(
        _ index: Signal<Int>, by delta: Int, within count: CellID, wrap: Bool = false
    ) -> BehaviorInvocation {
        BehaviorInvocation(
            name: WireBehavior.listMove, cell: index.id,
            params: [.int(Int64(delta)), .int(Int64(count.raw)), .bool(wrap)])
    }
    /// `listMove` bounded by a `Signal<Int>` length.
    public static func listMove(
        _ index: Signal<Int>, by delta: Int, within count: Signal<Int>, wrap: Bool = false
    ) -> BehaviorInvocation {
        listMove(index, by: delta, within: count.id, wrap: wrap)
    }
    /// `listMove` bounded by a `Computed<Int>` length (e.g. the P5 `count` of a filtered client list).
    public static func listMove(
        _ index: Signal<Int>, by delta: Int, within count: Computed<Int>, wrap: Bool = false
    ) -> BehaviorInvocation {
        listMove(index, by: delta, within: count.id, wrap: wrap)
    }

    /// Append the current text of `query` to the `tokens` array and clear `query` — the token-field
    /// commit (type text, press Enter → a new chip, input cleared). A no-op when `query` is empty.
    public static func commit(_ tokens: Signal<[String]>, from query: Signal<String>) -> BehaviorInvocation {
        BehaviorInvocation(name: WireBehavior.commit, cell: tokens.id, params: [.int(Int64(query.id.raw))])
    }

    /// Remove the last element of a string array — backspace-on-empty removes the last chip. A no-op when
    /// the triggering element has a non-empty `value` (so Backspace deletes text while typing, not a chip).
    public static func removeLast(_ tokens: Signal<[String]>) -> BehaviorInvocation {
        BehaviorInvocation(name: WireBehavior.removeLast, cell: tokens.id)
    }

    /// Append the **triggering element's text** to `tokens` and clear `query` — click a suggestion to
    /// commit it (P9). A no-op when the element's text is empty.
    public static func commitValue(_ tokens: Signal<[String]>, clearing query: Signal<String>)
        -> BehaviorInvocation
    {
        BehaviorInvocation(name: WireBehavior.commitValue, cell: tokens.id, params: [.int(Int64(query.id.raw))])
    }
}

// MARK: - leading-dot call-site factories — `.on(.click, .increment($qty))` (ADR-0015)

/// The same closed behaviors as ``Behavior``, surfaced on ``BehaviorInvocation`` so a call site can use the
/// leading-dot form: `.on(.click, .increment($qty))` rather than `.on(.click, Behavior.increment($qty))`.
extension BehaviorInvocation {
    /// Set `signal` to a constant value.
    public static func set<Value: WireEncodable>(_ signal: Signal<Value>, to value: Value) -> BehaviorInvocation {
        Behavior.set(signal, to: value)
    }
    /// Toggle a boolean signal.
    public static func toggle(_ signal: Signal<Bool>) -> BehaviorInvocation { Behavior.toggle(signal) }
    /// Add `step` to an integer signal.
    public static func increment(_ signal: Signal<Int>, by step: Int = 1) -> BehaviorInvocation {
        Behavior.increment(signal, by: step)
    }
    /// Set a string signal from the triggering element's `value`.
    public static func setFromValue(_ signal: Signal<String>) -> BehaviorInvocation {
        Behavior.setFromValue(signal)
    }
    /// Append the current text of `query` to `tokens` and clear `query`.
    public static func commit(_ tokens: Signal<[String]>, from query: Signal<String>) -> BehaviorInvocation {
        Behavior.commit(tokens, from: query)
    }
    /// Remove the last element of a string array.
    public static func removeLast(_ tokens: Signal<[String]>) -> BehaviorInvocation { Behavior.removeLast(tokens) }
    /// Append the triggering element's text to `tokens` and clear `query`.
    public static func commitValue(_ tokens: Signal<[String]>, clearing query: Signal<String>) -> BehaviorInvocation {
        Behavior.commitValue(tokens, clearing: query)
    }
}

extension WireValue {
    /// A scalar wire value as a single attribute token. Arrays/null are not valid behavior params.
    var scalarToken: String {
        switch self {
            case .null, .array: ""
            case .bool(let bool): bool ? "true" : "false"
            case .int(let int): String(int)
            case .double(let double): String(double)
            case .string(let string): string
        }
    }
}
