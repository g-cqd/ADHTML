// HTMLToken — the output of the HTML tokenizer (the WHATWG "tokenization" stage, what
// WebKit's HTMLTokenizer emits). Character data is coalesced into `.text` runs (the
// spec emits per-code-point; coalescing is observably equivalent and far more usable).
public enum HTMLToken: Sendable, Equatable {
    case startTag(name: String, attributes: [HTMLAttribute], selfClosing: Bool)
    case endTag(name: String)
    case text(String)
    case comment(String)
    case doctype(name: String?)
}

/// A start-tag attribute (name lowercased; value entity-decoded).
public struct HTMLAttribute: Sendable, Equatable {
    public let name: String
    public let value: String
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}
