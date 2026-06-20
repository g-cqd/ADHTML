// An order-preserving set of attributes for one element. Backed by a small `[Entry]` array (not a
// hashed dictionary): an element carries a handful of attributes, and for small N a contiguous array
// with a linear scan beats a hash map — no per-element hashing, no dictionary allocation, and cache-
// friendly iteration. Insertion order is preserved (required for stable ETags and island/cache IDs,
// RFC-0002 §6); `class` and `style` **auto-merge** (space- and `;`-separated); every other attribute
// overwrites in place on repeat. Crucially, `entries` returns the backing array directly (a CoW ref,
// no copy), so lowering an element no longer allocates an array per element (a hot-path win, ADR-0013).
public struct AttributeStore: Sendable {
    /// One attribute: its name, value, and the escaping context its value must be emitted in.
    public struct Entry: Sendable {
        public var name: String
        public var value: String
        public var context: EscapeContext
    }

    private var storage: [Entry] = []

    /// An empty store.
    public static let empty = AttributeStore()

    public init() {}

    /// Set (or merge) an attribute. `class`/`style` append to any existing value with the correct
    /// separator (in place, preserving position); all others overwrite. New attributes append in order.
    public mutating func set(_ name: String, _ value: String, context: EscapeContext) {
        for index in storage.indices where storage[index].name == name {
            switch name {
                case "class": storage[index].value += " " + value
                // `style` and the class-merge directive both accumulate `;`-separated (the P2 wire is
                // `name:cell;name2:cell2`, so repeated `.classToggle` coalesces into one attribute).
                case "style", WireToken.classToggle: storage[index].value += ";" + value
                default: storage[index] = Entry(name: name, value: value, context: context)
            }
            return
        }
        storage.append(Entry(name: name, value: value, context: context))
    }

    /// The attributes in insertion order. Returns the backing array directly (no copy).
    public var entries: [Entry] { storage }
}
