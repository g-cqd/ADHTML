// The call-site half of a server action (RFC-0020 Track 3 P2): a `<form>` that posts to the signed
// endpoint. It composes EXISTING pieces only — the RFC-0019 `Action` (the runtime fetch+morph path) +
// a native `<form method=post action=…>` (the no-JS fallback) + the signed token as a hidden field. No
// new wire token, no client/runtime change. Hand-used in P2 (the author mints the token and passes it);
// the `@Endpoint` macro (P3) generates this call with the token minted from an ambient signer.

public import ADHTMLCore  // HTML, form/input/button, Action, RegionID

/// A hidden form field — rides the POST body on both paths (`new FormData(form)` for the runtime fetch,
/// the native submit for no-JS), so the runtime never needs to know a field is an action token.
public func Hidden(_ name: String, _ value: String) -> some HTML {
    input().attribute("type", "hidden").attribute("name", name).attribute("value", value)
}

/// A `<form>` that invokes the server action `id`, signed by `token`, re-rendering the `region`. Put the
/// action's value fields (e.g. `Hidden("id", "7")`) and the submit control in `content`.
///
/// Emits three things over the SAME markup: the native `method=post action="/_adh/act/<id>"` (the no-JS
/// fallback — submits to the signed endpoint, which 303-redirects back), the RFC-0019 client `Action`
/// (`data-p/q/u/v` — the runtime fetches + morphs the region), and the hidden `_adh` token (verified
/// server-side before the handler runs).
public func ServerActionForm<Content: HTML>(
    _ id: ActionID, token: String, target region: RegionID, @HTMLBuilder _ content: () -> Content
) -> some HTML {
    let path = "/_adh/act/\(id.raw)"
    return form {
        Hidden("_adh", token)
        content()
    }
    .attribute("method", "post")
    .attribute("action", path)
    .action(.post(path).target(region.islandID))
}
