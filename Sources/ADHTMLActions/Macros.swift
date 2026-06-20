// ADHTMLActions' macro declarations (implementations in the `ADHTMLMacros` plugin). RFC-0020 Track 3 P3.
// NOTE the deliberate name: `@Action` (a macro, attribute position) coexists with ADHTMLCore's `Action`
// (a struct, type position) — Swift resolves them in separate lookup contexts, and it reads as ONE concept
// in two layers (a server `@Action` handler is reached via a client `Action` under the hood).

public import ADHTMLCore  // RegionID

/// Mark a `static func (_ ctx) throws -> ResponseContent` as a server action: a typed, signed, region-bound
/// mutation handler reachable from a `<form>` (`.submits(to:)`), with a no-JS PRG fallback. `into` is the
/// ``Region`` the response re-renders; `page` is the optional no-JS Post/Redirect/Get target (the page to
/// 303 back to without JS). Adds the typed call-site handle `<func>Action`.
@attached(peer, names: suffixed(Action))
public macro Action(_ slug: String, into region: RegionID, page: String? = nil) =
    #externalMacro(module: "ADHTMLMacros", type: "ActionMacro")

/// Collect the `@Action` handlers declared in this namespace into `static let all: [ServerAction]` — the
/// boot registry, composable across namespaces: `ServerActionTable(PartActions.all + OrderActions.all)
/// .dispatchRoute(signer:now:)`. So adding an action is one annotated func, never a second hand-maintained
/// list. (Collection is per-namespace — Swift can't link-scan static registrations — so one `@Actions enum`
/// per feature, concatenated at the app root.)
@attached(member, names: named(all))
public macro Actions() =
    #externalMacro(module: "ADHTMLMacros", type: "ActionsMacro")
