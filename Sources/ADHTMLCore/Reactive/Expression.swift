// A closed, serializable expression language for client-recomputable computeds (RFC-0003). A normal
// `computed { … }` wraps an opaque Swift closure the client cannot re-run, so its value is server-fixed
// (updated only by an SSE patch). A `computed(_ reactive:)` instead takes a `Reactive` built from a
// CLOSED operator DSL — it is evaluated once server-side for the initial value AND serialized as a
// `WireExpr` the client re-evaluates reactively, so derived cells update in-browser with no round-trip.
//
// The op set is intentionally small and total (no division-by-zero or partial ops in v1): arithmetic on
// `Int`/`Double`, and `String` concatenation. It composes — `count.reactive * 2 + base.reactive` — and
// extends by adding a `BinaryOp` case here plus its mirror in the client evaluator (a parity test guards
// the two stay in sync).

/// A node in the closed client-recomputable expression tree (serialized into a `cmp` cell's `e` field).
public enum WireExpr: Sendable, Equatable {
    /// A reference to another cell (by id; reindexed at serialization, like a dependency).
    case cell(CellID)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case string(String)
    /// A binary operation over two sub-expressions.
    indirect case binary(BinaryOp, WireExpr, WireExpr)
}

/// The closed binary operator set. Raw values are the wire tokens; the client evaluator mirrors them
/// (a Swift test + a JS test each pin the same token set — add an op → update both sides).
public enum BinaryOp: String, Sendable, Equatable, CaseIterable {
    case add = "+"
    case sub = "-"
    case mul = "*"
    case concat = "++"
}

extension WireExpr {
    /// Every cell this expression references (for the computed's dependency set). Iterative — no
    /// recursion over the tree (ADR-0002).
    var cellRefs: [CellID] {
        var refs: [CellID] = []
        var stack: [WireExpr] = [self]
        while let node = stack.popLast() {
            switch node {
                case .cell(let id): refs.append(id)
                case .binary(_, let lhs, let rhs):
                    stack.append(lhs)
                    stack.append(rhs)
                default: break
            }
        }
        return refs
    }
}

/// A value-type expression operand: the `WireExpr` to serialize plus its server-evaluated `value` (so a
/// `Reactive` doubles as the initial value and the client formula). Build them from `Signal`/`Computed`
/// via `.reactive`, from literals, and the operators below.
public struct Reactive<Value: WireEncodable>: Sendable {
    public let expr: WireExpr
    public let value: Value

    public init(_ expr: WireExpr, _ value: Value) {
        self.expr = expr
        self.value = value
    }
}

extension Signal {
    /// This signal as a `Reactive` operand: a cell reference plus its current value.
    public var reactive: Reactive<Value> { Reactive(.cell(id), value) }
}

extension Computed {
    /// This computed as a `Reactive` operand: a cell reference plus its evaluated value.
    public var reactive: Reactive<Value> { Reactive(.cell(id), value) }
}

// MARK: - Literals

extension Reactive: ExpressibleByIntegerLiteral where Value == Int {
    public init(integerLiteral value: Int) { self.init(.int(Int64(value)), value) }
}
extension Reactive: ExpressibleByFloatLiteral where Value == Double {
    public init(floatLiteral value: Double) { self.init(.double(value), value) }
}
extension Reactive: ExpressibleByUnicodeScalarLiteral where Value == String {
    public init(unicodeScalarLiteral value: String) { self.init(.string(value), value) }
}
extension Reactive: ExpressibleByExtendedGraphemeClusterLiteral where Value == String {
    public init(extendedGraphemeClusterLiteral value: String) { self.init(.string(value), value) }
}
extension Reactive: ExpressibleByStringLiteral where Value == String {
    public init(stringLiteral value: String) { self.init(.string(value), value) }
}
extension Reactive: ExpressibleByBooleanLiteral where Value == Bool {
    public init(booleanLiteral value: Bool) { self.init(.bool(value), value) }
}

// MARK: - Operators (closed, total)

/// Reactive addition (`Int`/`Double`).
public func + <V: WireEncodable & AdditiveArithmetic>(lhs: Reactive<V>, rhs: Reactive<V>) -> Reactive<V> {
    Reactive(.binary(.add, lhs.expr, rhs.expr), lhs.value + rhs.value)
}
/// Reactive subtraction (`Int`/`Double`).
public func - <V: WireEncodable & AdditiveArithmetic>(lhs: Reactive<V>, rhs: Reactive<V>) -> Reactive<V> {
    Reactive(.binary(.sub, lhs.expr, rhs.expr), lhs.value - rhs.value)
}
/// Reactive multiplication (`Int`/`Double`).
public func * <V: WireEncodable & Numeric>(lhs: Reactive<V>, rhs: Reactive<V>) -> Reactive<V> {
    Reactive(.binary(.mul, lhs.expr, rhs.expr), lhs.value * rhs.value)
}
/// Reactive string concatenation.
public func + (lhs: Reactive<String>, rhs: Reactive<String>) -> Reactive<String> {
    Reactive(.binary(.concat, lhs.expr, rhs.expr), lhs.value + rhs.value)
}
