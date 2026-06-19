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
    /// Set `signal` to a constant value.
    public static func set<Value: WireEncodable>(_ signal: Signal<Value>, to value: Value)
        -> BehaviorInvocation
    {
        BehaviorInvocation(name: "set", cell: signal.id, params: [value.wireValue])
    }

    /// Toggle a boolean signal.
    public static func toggle(_ signal: Signal<Bool>) -> BehaviorInvocation {
        BehaviorInvocation(name: "toggle", cell: signal.id)
    }

    /// Add `step` to an integer signal.
    public static func increment(_ signal: Signal<Int>, by step: Int = 1) -> BehaviorInvocation {
        BehaviorInvocation(name: "increment", cell: signal.id, params: [.int(Int64(step))])
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
