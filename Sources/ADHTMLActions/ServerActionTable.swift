// The server-action registry + the single signed dispatch route (RFC-0020 Track 3 P2). Every action
// dispatches through ONE route — `POST /_adh/act/{id}` — which is the single security chokepoint: it
// verifies the signed token, matches it to the path id, looks up the registered handler, checks expiry +
// the CSRF session binding, then runs the handler. The handler returns the re-rendered Region; on a runtime
// (`ADH-Request`) request that fragment morphs in place, and on a no-JS native form POST the dispatcher
// answers with a 303 See Other to the action's return path (Post/Redirect/Get, RFC 9110 §15.4.4).
//
// CSRF model (read before trusting it): the session cookie's `SameSite=Lax` is the PRIMARY control — it
// blocks the cross-site POST from carrying the session at all. The per-token `sid` binding here is
// defence-in-depth on top of it: it rejects a same-site cross-session replay (a token lifted from victim A
// submitted under B's session). It is NOT a standalone CSRF defence — a session-less deployment binds every
// token to `-` and leans entirely on `SameSite`. Use `requiresSession` for mutating actions on a
// session-bearing app, and do not set the session cookie to `SameSite=None` without re-evaluating this.

public import ADServeCore  // ResponseContent, HTTPError
public import ADServeDSL  // POST, RouteNode, StorageContext, PathParameters

/// One registered server action: the handler + its policy. `handler` is `@Sendable` and runs on the shared
/// pool's `StorageContext` (app services via `ctx`, no captured state — the boot/no-capture wall).
public struct ServerAction: Sendable {
    public let id: ActionID
    /// The no-JS Post/Redirect/Get target — where a native form POST is 303-redirected after the mutation.
    /// `nil` falls back to `/`. A same-origin `Referer` default is deferred: the security review showed it is
    /// the attacker-influenced part of the redirect (CWE-601), so set this (`page:`) for a precise no-JS
    /// redirect rather than relying on the request's `Referer`.
    public let returnPath: String?
    /// Reject a session-less request (no `Sessions` cookie) up front when `true` — use it for mutating
    /// actions on a session-bearing app so the per-token CSRF binding is load-bearing, not silently `-`.
    public let requiresSession: Bool
    /// Token lifetime in seconds (the replay/expiry window minted into each token).
    public let ttl: Int
    public let handler: @Sendable (StorageContext) throws -> ResponseContent

    public init(
        slug: String, returnPath: String? = nil, requiresSession: Bool = false, ttl: Int = 300,
        handler: @escaping @Sendable (StorageContext) throws -> ResponseContent
    ) {
        self.id = ActionID(slug: slug)
        self.returnPath = returnPath
        self.requiresSession = requiresSession
        self.ttl = ttl
        self.handler = handler
    }
}

/// The frozen-at-boot id → action registry. Built once, read concurrently by the dispatch route.
public struct ServerActionTable: Sendable {
    @usableFromInline let actions: [String: ServerAction]

    /// Build from the app's action list. A duplicate id (a slug-hash collision) is a boot precondition
    /// failure — fail fast, never a silent mis-dispatch.
    public init(_ list: [ServerAction]) {
        var map: [String: ServerAction] = [:]
        for action in list {
            precondition(
                map[action.id.raw] == nil, "duplicate server-action id '\(action.id.raw)' (slug-hash collision)")
            map[action.id.raw] = action
        }
        self.actions = map
    }

    @usableFromInline func action(for id: String) -> ServerAction? { actions[id] }

    /// The verification outcome — pure + unit-testable (no request/server). `.run` carries the resolved
    /// action; `.forbidden`'s reason is for tests/logs only (the route returns an opaque 403, no oracle).
    @usableFromInline enum Resolution: Equatable, Sendable {
        case run(ActionID)
        case forbidden(String)
        case notFound
    }

    /// The fail-closed verification ladder, factored out of the route so it is testable without a server.
    /// Order matters: integrity FIRST (everything after reads now-trusted fields), then route-id match,
    /// registry lookup (404 — distinct from a tampered token), expiry, the session-required gate, then the
    /// constant-time CSRF binding compare.
    @usableFromInline func resolve(
        pathID: String?, token wire: String?, sessionCookie: String?, now: Int, signer: ActionSigner
    ) -> Resolution {
        guard let pathID else { return .forbidden("bad action") }
        guard let wire, let token = signer.verified(wire) else { return .forbidden("bad token") }  // HMAC gate
        guard token.id == pathID else { return .forbidden("action mismatch") }
        guard let action = action(for: token.id) else { return .notFound }
        guard now <= token.exp else { return .forbidden("expired") }
        let sid = ActionSigner.sessionBinding(of: sessionCookie)
        if action.requiresSession, sid == "-" { return .forbidden("session required") }
        guard ConstantTime.equal(token.sid, sid) else { return .forbidden("csrf") }  // constant-time: no byte oracle
        return .run(action.id)
    }

    /// The ONE route every server action dispatches through. Splice it into the app's `App { … }` route tree.
    /// `signer` verifies tokens; `now` is the injected clock (Unix seconds) for the expiry check. The CSRF
    /// binding is the request's `session` cookie value.
    public func dispatchRoute(signer: ActionSigner, now: @escaping @Sendable () -> Int) -> RouteNode {
        POST("/_adh/act/{id}", pool: .shared) {
            (ctx: StorageContext, params: PathParameters) throws -> ResponseContent in
            switch self.resolve(
                pathID: params["id"], token: ctx.form()["_adh"], sessionCookie: ctx.cookies["session"],
                now: now(), signer: signer)
            {
                // One opaque 403 for every rejection — the reason never leaks to the client (it stays in the
                // Resolution for tests/logs). 404 only for a valid token whose action was retired.
                case .forbidden(_): throw HTTPError.forbidden()
                case .notFound: throw HTTPError.notFound()
                case .run(let id):
                    let action = self.action(for: id.raw)!  // `resolve` already proved `id` is registered.
                    let result = try action.handler(ctx)
                    // Runtime request → return the fragment to morph; native no-JS POST → 303 PRG.
                    return ctx.isFragment ? result : .redirect(to: action.returnPath ?? "/")
            }
        }
        .maxBody(64 * 1024)  // an action form is a few hundred bytes; cap the parse + verify work per request
    }
}

/// Constant-time comparison primitives — a caseless-enum namespace.
enum ConstantTime {
    /// Constant-time UTF-8 equality (no early exit on the first differing byte → closes the timing oracle
    /// on the CSRF binding compare; the length difference is mixed in, so it is length-safe too).
    @usableFromInline static func equal(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8)
        let y = Array(b.utf8)
        var diff = UInt8(x.count == y.count ? 0 : 1)
        for index in 0 ..< Swift.max(x.count, y.count) {
            diff |= (index < x.count ? x[index] : 0) ^ (index < y.count ? y[index] : 0)
        }
        return diff == 0
    }
}
