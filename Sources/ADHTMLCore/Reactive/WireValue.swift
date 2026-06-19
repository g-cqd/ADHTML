// A serializable value carried by a reactive cell (RFC-0003 / ADR-0007). Deliberately independent of
// ADJSON — the core stays lean and the wire serializer (Wire/) bridges `WireValue` to JSON bytes via
// ADJSON at emit time. Scalars + arrays cover Phase-1 state; object-valued cells are a later addition.

/// A value a reactive cell can hold and serialize to the hydration wire format.
public enum WireValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    indirect case array([WireValue])
}

/// A type that can be carried by a reactive cell and serialized to the wire format.
public protocol WireEncodable: Sendable {
    var wireValue: WireValue { get }
}

extension Bool: WireEncodable { public var wireValue: WireValue { .bool(self) } }
extension Int: WireEncodable { public var wireValue: WireValue { .int(Int64(self)) } }
extension Int64: WireEncodable { public var wireValue: WireValue { .int(self) } }
extension Double: WireEncodable { public var wireValue: WireValue { .double(self) } }
extension String: WireEncodable { public var wireValue: WireValue { .string(self) } }

extension Array: WireEncodable where Element: WireEncodable {
    public var wireValue: WireValue { .array(map(\.wireValue)) }
}

extension Optional: WireEncodable where Wrapped: WireEncodable {
    public var wireValue: WireValue { self?.wireValue ?? .null }
}
