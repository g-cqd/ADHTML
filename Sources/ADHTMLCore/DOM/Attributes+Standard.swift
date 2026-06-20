// Attribute modifiers. Global attributes apply to every element; trait-gated modifiers compile only on
// elements that may carry the attribute (ADR-0009). Values are escaped in the right context: URLs use
// the scheme-allowlisted `.url` context, `style` uses `.css`, the rest use `.attribute`.
//
// Every modifier is `consuming` and forwards to `HTMLElement.attribute`, which is also `consuming`: a
// modifier chain on a dying temporary *moves* the element through the chain, so the attribute store is
// uniquely held and mutated in place (one allocation for the chain, not one deep copy per link).

extension HTMLElement {
    /// `title` (advisory tooltip text).
    public consuming func title(_ value: String) -> Self { attribute("title", value) }
    /// `lang`.
    public consuming func lang(_ value: String) -> Self { attribute("lang", value) }
    /// `dir` (`ltr`/`rtl`/`auto`).
    public consuming func dir(_ value: String) -> Self { attribute("dir", value) }
    /// ARIA `role`.
    public consuming func role(_ value: String) -> Self { attribute("role", value) }
    /// `tabindex`.
    public consuming func tabIndex(_ value: Int) -> Self { attribute("tabindex", String(value)) }
    /// Inline `style` (CSS-escaped).
    public consuming func style(_ value: String) -> Self { attribute("style", value, context: .css) }
    /// The boolean `hidden` attribute (present when `on`).
    public consuming func hidden(_ on: Bool = true) -> Self { on ? attribute("hidden", "") : self }
    /// A `data-<name>` attribute.
    public consuming func data(_ name: String, _ value: String) -> Self { attribute("data-\(name)", value) }
    /// An `aria-<name>` attribute.
    public consuming func aria(_ name: String, _ value: String) -> Self { attribute("aria-\(name)", value) }
}

extension HTMLElement where Tag: HasHref {
    /// `href` (scheme-allowlisted URL — `javascript:`/`data:` rejected, ADR-0003). Offered only on tags
    /// that may carry one (`<a>`, `<area>`, `<link>`, `<base>`).
    public consuming func href(_ value: String) -> Self { attribute("href", value, context: .url) }
}
extension HTMLElement where Tag: HasSrc {
    /// `src` (scheme-allowlisted URL).
    public consuming func src(_ value: String) -> Self { attribute("src", value, context: .url) }
}
extension HTMLElement where Tag: HasType {
    /// `type`.
    public consuming func type(_ value: String) -> Self { attribute("type", value) }
}
extension HTMLElement where Tag: HasName {
    /// `name`.
    public consuming func name(_ value: String) -> Self { attribute("name", value) }
}
extension HTMLElement where Tag: HasValue {
    /// `value`.
    public consuming func value(_ value: String) -> Self { attribute("value", value) }
}
extension HTMLElement where Tag: HasPlaceholder {
    /// `placeholder`.
    public consuming func placeholder(_ value: String) -> Self { attribute("placeholder", value) }
}
extension HTMLElement where Tag: HasFor {
    /// The `for` attribute (named `htmlFor` since `for` is a keyword).
    public consuming func htmlFor(_ value: String) -> Self { attribute("for", value) }
}
extension HTMLElement where Tag: HasDisabled {
    /// The boolean `disabled` attribute (present when `on`).
    public consuming func disabled(_ on: Bool = true) -> Self { on ? attribute("disabled", "") : self }
}
extension HTMLElement where Tag: HasAlt {
    /// `alt` (alternative text).
    public consuming func alt(_ value: String) -> Self { attribute("alt", value) }
}
extension HTMLElement where Tag: HasRel {
    /// `rel`.
    public consuming func rel(_ value: String) -> Self { attribute("rel", value) }
}
extension HTMLElement where Tag: HasTarget {
    /// `target` (e.g. `_blank`, `_self`).
    public consuming func target(_ value: String) -> Self { attribute("target", value) }
}
extension HTMLElement where Tag: HasContent {
    /// `content` (`<meta>` value).
    public consuming func content(_ value: String) -> Self { attribute("content", value) }
}
extension HTMLElement where Tag: HasAction {
    /// `action` (form submission URL — scheme-allowlisted).
    public consuming func action(_ value: String) -> Self { attribute("action", value, context: .url) }
}
extension HTMLElement where Tag: HasMethod {
    /// `method` (`get`/`post`/`dialog`).
    public consuming func method(_ value: String) -> Self { attribute("method", value) }
}
