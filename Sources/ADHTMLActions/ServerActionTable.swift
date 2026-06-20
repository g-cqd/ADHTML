// The server-action registry + the single signed dispatch route (RFC-0020 Track 3 P2). Every action
// dispatches through ONE route — `POST /_adh/act/{id}` — which is the single security chokepoint: it
// verifies the signed token, matches it to the path id, looks up the registered handler, checks expiry +
// the CSRF session binding, then runs the handler. The handler returns the re-rendered Region; on a
// runtime (`ADH-Request`) request that fragment morphs in place, and on a no-JS native form POST the
// dispatcher answers with a 303 See Other to the action's return path (Post/Redirect/Get, RFC 9110 §15.4.4).

public import ADServeCore  // ResponseContent, HTTPError
public import ADServeDSL  // POST, RouteNode, StorageContext, PathParameters

/// One registered server action: the handler + its policy. `handler` is `@Sendable` and runs on the shared
/// pool's `StorageContext` (app services via `ctx`, no captured state — the boot/no-capture wall).
public struct ServerAction: Sendable {
    public let id: ActionID
    /// The no-JS Post/Redirect/Get target — where a native form POST is 303-redirected after the mutation.
    public let returnPath: String
    /// Token lifetime in seconds (the replay/expiry window minted into each token).
    public let ttl: Int
    public let handler: @Sendable (StorageContext) throws -> ResponseContent

    public init(
        slug: String, returnPath: String, ttl: Int = 3600,
        handler: @escaping @Sendable (StorageContext) throws -> ResponseContent
    ) {
        self.id = ActionID(slug: slug)
        self.returnPath = returnPath
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
    /// action; the rejections map 1:1 to the dispatch route's fail-closed responses.
    @usableFromInline enum Resolution: Equatable, Sendable {
        case run(ActionID)
        case forbidden(String)
        case notFound
    }

    /// The fail-closed verification ladder, factored out of the route so it is testable without a server.
    /// Order matters: integrity FIRST (everything after reads now-trusted fields), then route-id match,
    /// registry lookup (404 — distinct from a tampered token), expiry, then the CSRF session binding.
    @usableFromInline func resolve(
        pathID: String?, token wire: String?, sessionBinding: String?, now: Int, signer: ActionSigner
    ) -> Resolution {
        guard let pathID else { return .forbidden("bad action") }
        guard let wire, let token = signer.verified(wire) else { return .forbidden("bad token") }
        guard token.id == pathID else { return .forbidden("action mismatch") }
        guard let action = action(for: token.id) else { return .notFound }
        guard now <= token.exp else { return .forbidden("expired") }
        guard token.sid8 == ActionSigner.sid8(of: sessionBinding) else { return .forbidden("csrf") }
        return .run(action.id)
    }

    /// The ONE route every server action dispatches through. Splice it into the app's `App { … }` route
    /// tree. `signer` verifies tokens; `now` is the injected clock (seconds since the Unix epoch) for the
    /// expiry check. The CSRF binding is the request's `session` cookie value (P2; a configurable cookie /
    /// `Session.id` binding is a follow-up).
    public func dispatchRoute(signer: ActionSigner, now: @escaping @Sendable () -> Int) -> RouteNode {
        POST("/_adh/act/{id}", pool: .shared) {
            (ctx: StorageContext, params: PathParameters) throws -> ResponseContent in
            switch self.resolve(
                pathID: params["id"], token: ctx.form()["_adh"], sessionBinding: ctx.cookies["session"],
                now: now(), signer: signer)
            {
                case .forbidden(let reason): throw HTTPError.forbidden(reason)
                case .notFound: throw HTTPError.notFound()
                case .run(let id):
                    // `resolve` already proved `id` is registered.
                    let action = self.action(for: id.raw)!
                    let result = try action.handler(ctx)
                    // Runtime request → return the fragment to morph; native no-JS POST → 303 PRG.
                    return ctx.isFragment ? result : .redirect(to: action.returnPath)
            }
        }
    }
}
