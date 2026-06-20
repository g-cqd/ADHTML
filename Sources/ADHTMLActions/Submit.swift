// The call-site sugar for server actions (RFC-0020 Track 3 P3): `.submits(to:)` makes a `<form>` post to a
// signed `@Action`, minting the token from an AMBIENT signer so the author never threads one. The signer is
// installed per-request by `ctx.actionView(signer:page:fragment:)` and carried by `@TaskLocal` (restores at
// scope exit, data-race-free across a streaming render — same rationale as `ADHTMLRenderContext`). It reuses
// the RFC-0019 `Action` + a native form fallback verbatim — no new wire token, no client/runtime change.

public import ADHTMLCore  // HTML, form, the Action STRUCT, RegionID, Tags.Form
public import ADServeCore  // ResponseContent
public import ADServeDSL  // HandlerContext

internal import ADHTMLNIO  // ctx.view (the page/fragment render the action signer wraps)

/// The per-request action-signing context installed around a render so `.submits(to:)` can mint a token.
public enum ActionRenderContext {
    /// The active signing context, or `nil` outside an action render (then `.submits` emits an empty token —
    /// the form still posts, and the server rejects the unsigned request: fail-closed).
    @TaskLocal public static var current: Signing?

    /// The signer + the request's session cookie (the CSRF binding source) + the mint clock for one render.
    public struct Signing: Sendable {
        let signer: ActionSigner
        let sessionCookie: String?
        let now: Int
        /// The default token lifetime (seconds) minted at the call site — short, to bound the replay window.
        static let ttl = 300

        init(signer: ActionSigner, sessionCookie: String?, now: Int) {
            self.signer = signer
            self.sessionCookie = sessionCookie
            self.now = now
        }

        func token(for id: ActionID) -> String {
            signer.mint(id: id.raw, ttl: Self.ttl, sessionCookie: sessionCookie, now: now)
        }
    }
}

extension HandlerContext {
    /// Like ``ResponseContent`` `ctx.view(page:fragment:)`, but installs the ambient ``ActionSigner`` for the
    /// render so every `.submits(to:)` in the view mints its token automatically. Pass the app's boot signer
    /// and a `now` clock (seconds since the Unix epoch) — kept explicit so ADHTMLActions stays Foundation-free.
    public func actionView<Page: HTML, Fragment: HTML>(
        signer: ActionSigner, now: Int,
        @HTMLBuilder page: () -> Page, @HTMLBuilder fragment: () -> Fragment
    ) throws -> ResponseContent {
        try ActionRenderContext.$current.withValue(
            ActionRenderContext.Signing(signer: signer, sessionCookie: cookies["session"], now: now)
        ) {
            try view(page: page, fragment: fragment)
        }
    }
}

extension HTMLElement where Tag == Tags.Form {
    /// Make this `<form>` submit to the server `@Action` named by `handle`: injects the signed `_adh` token +
    /// the `values` as hidden fields, the native `method`/`action` (the no-JS fallback), and the RFC-0019
    /// client `Action` (`data-p/q/u` — the runtime fetches + morphs the handle's ``Region``). The token is
    /// minted from the ambient signer (install it with ``HandlerContext/actionView(signer:now:page:fragment:)``).
    public consuming func submits(to handle: ActionHandle, values: [String: String] = [:]) -> some HTML {
        let token = ActionRenderContext.current?.token(for: handle.id) ?? ""
        let path = "/_adh/act/\(handle.id.raw)"
        let inner = content
        return form {
            Hidden("_adh", token)
            for (key, value) in values.sorted(by: { $0.key < $1.key }) {
                Hidden(key, value)
            }
            inner
        }
        .attribute("method", "post")
        .attribute("action", path)
        .action(.post(path).target(handle.region.islandID))
    }
}
