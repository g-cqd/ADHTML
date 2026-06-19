internal import OrderedCollections

/// An order-preserving set of attributes for one element. Backed by `OrderedCollections`'
/// `OrderedDictionary`, so the emitted byte order is **deterministic** (insertion order) — required
/// for stable ETags and island/cache IDs (RFC-0002 §6). `class` and `style` **auto-merge**
/// (space- and `;`-separated); every other attribute overwrites on repeat.
public struct AttributeStore: Sendable {
    /// One attribute: its name, value, and the escaping context its value must be emitted in.
    public struct Entry: Sendable {
        public var name: String
        public var value: String
        public var context: EscapeContext
    }

    private var storage: OrderedDictionary<String, Entry> = [:]

    /// An empty store.
    public static let empty = AttributeStore()

    public init() {}

    /// Set (or merge) an attribute. `class`/`style` append to any existing value with the correct
    /// separator; all others overwrite.
    public mutating func set(_ name: String, _ value: String, context: EscapeContext) {
        if let existing = storage[name] {
            switch name {
                case "class":
                    storage[name] = Entry(name: name, value: existing.value + " " + value, context: existing.context)
                case "style":
                    storage[name] = Entry(name: name, value: existing.value + ";" + value, context: existing.context)
                default:
                    storage[name] = Entry(name: name, value: value, context: context)
            }
        } else {
            storage[name] = Entry(name: name, value: value, context: context)
        }
    }

    /// The attributes in insertion order.
    public var entries: [Entry] { Array(storage.values) }
}
