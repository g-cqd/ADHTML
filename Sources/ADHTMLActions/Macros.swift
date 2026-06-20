// ADHTMLActions' macro declarations (implementations in the `ADHTMLMacros` plugin). RFC-0020 Track 3 P3.
// NOTE the deliberate name: `@Action` (a macro, attribute position) coexists with ADHTMLCore's `Action`
// (a struct, type position) — Swift resolves them in separate lookup contexts, and it reads as ONE concept
// in two layers (a server `@Action` handler is reached via a client `Action` under the hood).

public import ADHTMLCore  // RegionID

/// Mark a `static func (_ ctx) throws -> ResponseContent` as a server action: a typed, signed, region-bound
/// mutation handler reachable from a `<form>` (`.submits(to:)`), with a no-JS PRG fallback. `into` is the
/// ``Region`` the response re-renders. Adds the typed call-site handle `<func>Action`.
@attached(peer, names: suffixed(Action))
public macro Action(_ slug: String, into region: RegionID) =
    #externalMacro(module: "ADHTMLMacros", type: "ActionMacro")
