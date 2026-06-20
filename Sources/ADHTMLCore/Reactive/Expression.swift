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
/// (a Swift test + a JS test each pin the same token set — add an op → update both sides). Arithmetic +
/// string concat yield the operand type; comparisons + boolean logic yield `Bool`. (Division and a
/// ternary are deliberately out of v1: `/` is partial, and a ternary needs a non-binary node.)
public enum BinaryOp: String, Sendable, Equatable, CaseIterable {
    case add = "+"
    case sub = "-"
    case mul = "*"
    case concat = "++"
    case eq = "=="
    case neq = "!="
    case lt = "<"
    case lte = "<="
    case gt = ">"
    case gte = ">="
    case and = "&&"
    case or = "||"
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

// MARK: - Comparisons (-> Reactive<Bool>)

public func == <V: WireEncodable & Equatable>(lhs: Reactive<V>, rhs: Reactive<V>) -> Reactive<Bool> {
    Reactive(.binary(.eq, lhs.expr, rhs.expr), lhs.value == rhs.value)
}
public func != <V: WireEncodable & Equatable>(lhs: Reactive<V>, rhs: Reactive<V>) -> Reactive<Bool> {
    Reactive(.binary(.neq, lhs.expr, rhs.expr), lhs.value != rhs.value)
}
public func < <V: WireEncodable & Comparable>(lhs: Reactive<V>, rhs: Reactive<V>) -> Reactive<Bool> {
    Reactive(.binary(.lt, lhs.expr, rhs.expr), lhs.value < rhs.value)
}
public func <= <V: WireEncodable & Comparable>(lhs: Reactive<V>, rhs: Reactive<V>) -> Reactive<Bool> {
    Reactive(.binary(.lte, lhs.expr, rhs.expr), lhs.value <= rhs.value)
}
public func > <V: WireEncodable & Comparable>(lhs: Reactive<V>, rhs: Reactive<V>) -> Reactive<Bool> {
    Reactive(.binary(.gt, lhs.expr, rhs.expr), lhs.value > rhs.value)
}
public func >= <V: WireEncodable & Comparable>(lhs: Reactive<V>, rhs: Reactive<V>) -> Reactive<Bool> {
    Reactive(.binary(.gte, lhs.expr, rhs.expr), lhs.value >= rhs.value)
}

// MARK: - Boolean logic (eager: both operands build the wire expr — not short-circuiting)

public func && (lhs: Reactive<Bool>, rhs: Reactive<Bool>) -> Reactive<Bool> {
    Reactive(.binary(.and, lhs.expr, rhs.expr), lhs.value && rhs.value)
}
public func || (lhs: Reactive<Bool>, rhs: Reactive<Bool>) -> Reactive<Bool> {
    Reactive(.binary(.or, lhs.expr, rhs.expr), lhs.value || rhs.value)
}
/// Logical NOT, modelled as `operand == false` so no extra (unary) node shape is needed.
public prefix func ! (operand: Reactive<Bool>) -> Reactive<Bool> {
    Reactive(.binary(.eq, operand.expr, .bool(false)), !operand.value)
}
