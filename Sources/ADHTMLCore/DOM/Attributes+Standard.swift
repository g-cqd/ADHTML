// Attribute modifiers. Global attributes apply to every element; trait-gated modifiers compile only on
// elements that may carry the attribute (ADR-0009). Values are escaped in the right context: URLs use
// the scheme-allowlisted `.url` context, `style` uses `.css`, the rest use `.attribute`.

extension HTMLElement {
    /// `title` (advisory tooltip text).
    public func title(_ value: String) -> Self { attribute("title", value) }
    /// `lang`.
    public func lang(_ value: String) -> Self { attribute("lang", value) }
    /// `dir` (`ltr`/`rtl`/`auto`).
    public func dir(_ value: String) -> Self { attribute("dir", value) }
    /// ARIA `role`.
    public func role(_ value: String) -> Self { attribute("role", value) }
    /// `tabindex`.
    public func tabIndex(_ value: Int) -> Self { attribute("tabindex", String(value)) }
    /// Inline `style` (CSS-escaped).
    public func style(_ value: String) -> Self { attribute("style", value, context: .css) }
    /// The boolean `hidden` attribute (present when `on`).
    public func hidden(_ on: Bool = true) -> Self { on ? attribute("hidden", "") : self }
    /// A `data-<name>` attribute.
    public func data(_ name: String, _ value: String) -> Self { attribute("data-\(name)", value) }
    /// An `aria-<name>` attribute.
    public func aria(_ name: String, _ value: String) -> Self { attribute("aria-\(name)", value) }
}

extension HTMLElement where Tag: HasSrc {
    /// `src` (scheme-allowlisted URL).
    public func src(_ value: String) -> Self { attribute("src", value, context: .url) }
}
extension HTMLElement where Tag: HasType {
    /// `type`.
    public func type(_ value: String) -> Self { attribute("type", value) }
}
extension HTMLElement where Tag: HasName {
    /// `name`.
    public func name(_ value: String) -> Self { attribute("name", value) }
}
extension HTMLElement where Tag: HasValue {
    /// `value`.
    public func value(_ value: String) -> Self { attribute("value", value) }
}
extension HTMLElement where Tag: HasPlaceholder {
    /// `placeholder`.
    public func placeholder(_ value: String) -> Self { attribute("placeholder", value) }
}
extension HTMLElement where Tag: HasFor {
    /// The `for` attribute (named `htmlFor` since `for` is a keyword).
    public func htmlFor(_ value: String) -> Self { attribute("for", value) }
}
extension HTMLElement where Tag: HasDisabled {
    /// The boolean `disabled` attribute (present when `on`).
    public func disabled(_ on: Bool = true) -> Self { on ? attribute("disabled", "") : self }
}
extension HTMLElement where Tag: HasAlt {
    /// `alt` (alternative text).
    public func alt(_ value: String) -> Self { attribute("alt", value) }
}
extension HTMLElement where Tag: HasRel {
    /// `rel`.
    public func rel(_ value: String) -> Self { attribute("rel", value) }
}
