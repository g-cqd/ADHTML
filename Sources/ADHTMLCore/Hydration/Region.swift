// A re-renderable region (RFC-0020 §1.6, ADR-0016). A `Region` is a thin, **stably-keyed** ``Island``:
// it is at once an in-page element AND the unit a server re-render targets — the same author-given key
// labels it in the full-page render and in any later fragment render, so an independent page-vs-fragment
// re-render still morphs the SAME element (a counter-inferred `c<n>` id would differ between the two and
// miss). It is the re-render unit for Tier-2 server actions and component-scoped assets, and the anchor a
// boosted `Link` / SSE stream morphs into.
//
// Unlike an implicit island (`c<scope>`), a `Region` stamps its key as BOTH `data-adh-id` (the SSE-morph /
// wiring selector) AND a plain `id` (what the RFC-0019 action interpreter resolves a morph target by, via
// `getElementById`). Because it is a real island in the wire, the document-level delegated listener
// delivers events fired inside it, and an inner ``Action`` with no explicit target defaults to it (the
// runtime walks to the nearest `data-adh-id`). Like ``Island``, `scope` is the data-leak boundary — empty
// by default (a pure morph anchor whose interactive children are their own islands), or the seed cells of
// any bindings written directly in the region.

/// A stable, author-given identifier for a ``Region`` — the key that survives an independent full-page vs
/// fragment re-render. Apps name their regions by extending it (`extension RegionID { static let content =
/// RegionID("content") }`), so call sites read `Region(.content)`. Shares the `data-adh-id` / `id` string
/// space with ``IslandID`` (both are just wire ids), so `.islandID` bridges to the action/island APIs.
public struct RegionID: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public init(stringLiteral value: String) { self.raw = value }
    public var description: String { raw }

    /// This region's id in the shared island/`data-adh-id` space — for `Action.target(_:)` and the wire.
    @inlinable public var islandID: IslandID { IslandID(raw) }
}

/// A stably-keyed, re-renderable region (RFC-0020 §1.6). Lowers to an island root carrying its key as both
/// `data-adh-id` and a plain `id`, so it is a morph target for SSE (`querySelector`) and for client
/// ``Action``s (`getElementById`) alike — and inner actions default their morph target to it.
public struct Region<Content: HTML>: HTML {
    public let id: RegionID
    public let on: LoadStrategy
    public let scope: [CellID]
    public let connect: String?
    public let content: Content

    /// Wrap `content` in a region keyed by `id`. `scope` is the data-leak boundary (default empty — a pure
    /// morph anchor; pass the seed cells of any bindings written directly in the region). `connect`
    /// subscribes the region to a live SSE morph/patch stream (RFC-0019 §6.3-H), like ``Island``.
    public init(
        _ id: RegionID,
        on: LoadStrategy = .load,
        scope: [CellID] = [],
        connect: String? = nil,
        @HTMLBuilder content: () -> Content
    ) {
        self.id = id
        self.on = on
        self.scope = scope
        self.connect = connect
        self.content = content()
    }

    @inlinable
    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        target.islandOpen(
            id: html.id.islandID, on: html.on, scope: html.scope, connect: html.connect, key: html.id.raw)
        Content._render(html.content, into: &target)
        target.islandClose()
    }
}
