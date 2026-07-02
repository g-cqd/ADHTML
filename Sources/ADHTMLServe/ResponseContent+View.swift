// RFC-0020 Tier-1 §1: "views, not bytes." A handler returns a VIEW; the host renders/fragments it. `.view`
// is the view-first alias over the buffered hydratable render (`.adhtml`), and `ctx.view(page:fragment:)`
// makes the page-vs-fragment choice IMPLICIT — driven by `ctx.isFragment` (RFC-0019 C1, the `ADH-Request`
// header) — so a handler never hand-writes the `if ctx.isFragment { .fragment } else { .html }` branch.
// Gated `ADHTML_SERVE` like the rest of the bridge (ADServeCore can't depend on ADHTML, so `.view` lives
// here, not in core). Reuses RFC-0019 transport unchanged — this is sugar over `.adhtml`/`.adhtmlFragment`.
public import ADHTMLCore
public import ADServeCore
public import ADServeDSL

extension ResponseContent {
    /// Render an ADHTML view as a full buffered `text/html` page (body + the inline hydration state). The
    /// view-first alias for `adhtml(_:arena:)` — a handler writes `return try .view(MyPage())`.
    public static func view(_ view: consuming some HTML, arena: CellArena = CellArena())
        throws(WireError) -> ResponseContent
    {
        try .adhtml(view, arena: arena)
    }
}

extension HandlerContext {
    /// Serve one route two ways from view declarations: the full `page` on a navigation, the `fragment` (a
    /// partial the runtime morphs) when the ADHTML runtime issued the request (`isFragment`). The choice is
    /// implicit — no hand-written `if ctx.isFragment` branch — and only the chosen builder is evaluated.
    public func view<Page: HTML, Fragment: HTML>(
        @HTMLBuilder page: () -> Page,
        @HTMLBuilder fragment: () -> Fragment
    ) throws(WireError) -> ResponseContent {
        if isFragment { return .adhtmlFragment(fragment()) }
        return try .adhtml(page())
    }
}
