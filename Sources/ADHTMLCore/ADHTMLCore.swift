/// ADHTMLCore — the Foundation-free render engine: the DOM value model, the iterative
/// (non-recursive) renderer, and context-aware escaping. See the design corpus under `docs/`
/// (RFC-0001…0004, ADR-0001…0012).
public enum ADHTMLCore {
    /// The hydration wire-format version this engine emits (RFC-0003 / ADR-0007). The client runtime
    /// refuses an unknown major; a CI test asserts the shipped runtime matches this value.
    public static let wireFormatVersion = 1
}
