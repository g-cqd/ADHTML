// Value-returning operators over `@State`'s projection (RFC-0005 §3.5). `@State`'s projected value `$count`
// is a ``Signal``; writing `$count > 0` or `$apples + $oranges` should read as ordinary Swift and yield the
// VALUE (`Bool`, `Int`, …) — the server-evaluated result. This lets `@Bound var inCart: Bool { $qty > 0 }`
// type-check with a value-typed annotation; the `@Bound` macro separately rewrites the SAME expression into
// the client-recomputable `WireExpr` (via the `.reactive` operand operators in `Expression.swift`).
//
// Each operator's LEFT operand is a CONCRETE ``Signal`` (never a free generic), so the signal goes on the
// left (`$qty + 1`, `$qty > 0`) and the operators are only candidates when the left operand is actually a
// signal — they never pollute operator resolution for unrelated types (`String + String`, `Int > Int`, …).

/// A readable reactive cell — its server value and its ``Reactive`` operand. ``Signal`` and ``Computed``
/// conform; it is the protocol behind the `$state` value operators below.
public protocol ReactiveReadable: Sendable {
    associatedtype Value: WireEncodable
    /// The server-evaluated value (records a dependency edge inside a computed, like ``Signal/value``).
    var value: Value { get }
    /// This cell as a ``Reactive`` operand (a cell reference plus its current value).
    var reactive: Reactive<Value> { get }
}

extension Signal: ReactiveReadable {}
extension Computed: ReactiveReadable {}

// MARK: - comparisons (-> Bool)

public func == <V: WireEncodable & Equatable>(lhs: Signal<V>, rhs: V) -> Bool { lhs.value == rhs }
public func != <V: WireEncodable & Equatable>(lhs: Signal<V>, rhs: V) -> Bool { lhs.value != rhs }
public func == <V: WireEncodable & Equatable>(lhs: Signal<V>, rhs: Signal<V>) -> Bool {
    lhs.value == rhs.value
}

public func < <V: WireEncodable & Comparable>(lhs: Signal<V>, rhs: V) -> Bool { lhs.value < rhs }
public func <= <V: WireEncodable & Comparable>(lhs: Signal<V>, rhs: V) -> Bool { lhs.value <= rhs }
public func > <V: WireEncodable & Comparable>(lhs: Signal<V>, rhs: V) -> Bool { lhs.value > rhs }
public func >= <V: WireEncodable & Comparable>(lhs: Signal<V>, rhs: V) -> Bool { lhs.value >= rhs }
public func < <V: WireEncodable & Comparable>(lhs: Signal<V>, rhs: Signal<V>) -> Bool {
    lhs.value < rhs.value
}
public func > <V: WireEncodable & Comparable>(lhs: Signal<V>, rhs: Signal<V>) -> Bool {
    lhs.value > rhs.value
}

// MARK: - arithmetic (-> Value)

public func + <V: WireEncodable & AdditiveArithmetic>(lhs: Signal<V>, rhs: V) -> V { lhs.value + rhs }
public func + <V: WireEncodable & AdditiveArithmetic>(lhs: Signal<V>, rhs: Signal<V>) -> V {
    lhs.value + rhs.value
}
public func - <V: WireEncodable & AdditiveArithmetic>(lhs: Signal<V>, rhs: V) -> V { lhs.value - rhs }
public func - <V: WireEncodable & AdditiveArithmetic>(lhs: Signal<V>, rhs: Signal<V>) -> V {
    lhs.value - rhs.value
}
public func * <V: WireEncodable & Numeric>(lhs: Signal<V>, rhs: V) -> V { lhs.value * rhs }
public func * <V: WireEncodable & Numeric>(lhs: Signal<V>, rhs: Signal<V>) -> V { lhs.value * rhs.value }

// String concatenation (`String` is not `AdditiveArithmetic`, so it needs its own `+`).
public func + (lhs: Signal<String>, rhs: String) -> String { lhs.value + rhs }
public func + (lhs: Signal<String>, rhs: Signal<String>) -> String { lhs.value + rhs.value }

// MARK: - boolean (-> Bool)

public func && (lhs: Signal<Bool>, rhs: Bool) -> Bool { lhs.value && rhs }
public func && (lhs: Signal<Bool>, rhs: Signal<Bool>) -> Bool { lhs.value && rhs.value }
public func || (lhs: Signal<Bool>, rhs: Bool) -> Bool { lhs.value || rhs }
public func || (lhs: Signal<Bool>, rhs: Signal<Bool>) -> Bool { lhs.value || rhs.value }
public prefix func ! (operand: Signal<Bool>) -> Bool { !operand.value }
