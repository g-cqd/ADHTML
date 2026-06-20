// `Link` boost — SPA-feel navigation (RFC-0021 P7, unblocks the prototype's S4/L7/D1/X2). A boosted link
// is a real `<a href>` that the runtime upgrades: a same-origin plain click fetches the destination as an
// ADH fragment (the `ADH-Request` header, contract C1) and morphs it into a named ``Region`` in place,
// then `history.pushState`s — so navigating swaps one region without a full reload, and Back/Forward
// re-morph it. The `<a href>` is the no-JS fallback by construction (a normal navigation), and any failure
// (offline, missing region, oversized body) falls back to a full navigation — a boost never strands the user.

/// A hyperlink — `<a href="path">title</a>`. On its own it is a normal navigation (the zero-JS baseline);
/// `.boost(into:)` upgrades it to in-page region navigation when the runtime is present.
public func Link(_ title: String, to path: String) -> HTMLElement<Tags.A, Text> {
    a { Text(title) }.href(path)
}

extension HTMLElement where Tag: HasHref {
    /// Boost this link: a same-origin plain click fetches `href` and morphs the response into the ``Region``
    /// keyed `region` (rather than navigating the whole page), then pushes history. Emits `data-adh-link`
    /// (the wire token the runtime intercepts). Without the runtime the link navigates normally (the
    /// `<a href>` fallback), so a boosted link always works. The target must be a ``Region`` (a stable `id`
    /// the response morphs into); a boost to a non-existent region degrades to a full navigation.
    public consuming func boost(into region: RegionID) -> Self {
        attribute(WireToken.link, region.raw)
    }
}
