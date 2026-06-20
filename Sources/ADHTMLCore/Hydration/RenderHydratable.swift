// The hydratable render entry: render HTML to bytes AND append the inline hydration state script for
// the islands found in the markup (RFC-0003). The islands are collected from the lowered program's
// `islandOpen` ops; the cell values + island scope come from `arena`; the serializer filters to the
// island-scope allowlist and scriptJSON-escapes the payload.

extension HTML {
    /// Render to HTML bytes followed by `<script type="application/adh-state+json" id="adh-state">…`
    /// carrying this render's island-scoped reactive state, ready for the client runtime to resume. This
    /// is the dynamic/stateful path, so it enforces an open-tag-depth ceiling (`maxDepth`, default
    /// ``Renderer/defaultMaxDepth``) and throws ``WireError/encoding(_:)`` on adversarial nesting rather
    /// than emitting unbounded output — the failure-safe contract (the iterative emit can't crash the
    /// stack, but the ceiling bounds pathological work).
    public consuming func renderHydratable(
        arena: CellArena, maxDepth: Int = Renderer.defaultMaxDepth
    ) throws(WireError) -> [UInt8] {
        // Install `arena` as the ambient context for the whole lowering pass, so a top-level
        // `@State`-bearing component registers its cells in THIS arena (and thus into the wire state),
        // and each nested component claims a fresh scope. `node` is a copy of the consumed `self`.
        var program = HTMLProgram()
        let node = self
        let assets = AssetSink()
        let root = ADHTMLRenderContext.Context(arena: arena, scope: arena.freshScope(), assets: assets)
        ADHTMLRenderContext.$current.withValue(root) {
            Self._render(node, into: &program)
        }

        // Collect islands AND enforce the depth ceiling in one iterative pass (open-tag accounting
        // mirrors Renderer.render): +1 on open / island-open, -1 on void-end / close / island-close.
        var islands: [WireIsland] = []
        var depth = 0
        for op in program.ops {
            switch op {
                case .openTagStart:
                    depth += 1
                case .islandOpen(let id, let on, let scope, _, _):
                    depth += 1
                    islands.append(WireIsland(id: id, on: on, scope: scope))
                case .voidTagEnd, .closeTag, .islandClose:
                    depth -= 1
                default:
                    break
            }
            if depth > maxDepth {
                throw WireError.encoding("open-tag nesting exceeded maxDepth \(maxDepth)")
            }
        }

        var sink = ArraySink(reservingCapacity: program.ops.count * 16)
        Renderer.render(program, into: &sink)

        let state = try WireSerializer.scriptBytes(cells: arena.cells, islands: islands)
        var out = sink.bytes
        // Component-scoped CSS (Track 4): inject the deduped `<style>` BEFORE the state script — present in
        // the initial response (no async load), so no-JS clients get the scoped styling and there is no FOUC.
        out.append(contentsOf: assets.styleTag())
        out.append(contentsOf: Self.scriptOpen)
        out.append(contentsOf: state)
        out.append(contentsOf: Self.scriptClose)
        return out
    }

    static var scriptOpen: [UInt8] {
        Array(#"<script type="application/adh-state+json" id="adh-state">"#.utf8)
    }
    static var scriptClose: [UInt8] { Array("</script>".utf8) }
}
