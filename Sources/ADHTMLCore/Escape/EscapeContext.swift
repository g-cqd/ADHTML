/// The output context an interpolated value is emitted in. Chosen by the element/attribute *type*,
/// never the author (ADR-0003), so a value cannot be placed unescaped by accident. Each context has
/// distinct escaping rules; see ``Escaper``.
public enum EscapeContext: Sendable {
    /// Element body text: escape `& < >`.
    case text
    /// A quoted attribute value: escape `& < > " '`.
    case attribute
    /// A URL attribute (`href`/`src`): scheme-allowlist, then escape. Rejects `javascript:`/`data:`.
    case url
    /// A `<style>`/`style=""` value.
    case css
    /// JSON embedded in a `<script>`: JSON-encode with `</`→`<\/` and U+2028/U+2029 escaped.
    case scriptJSON
}
