// The hydratable render entry: render HTML to bytes AND append the inline hydration state script for
// the islands found in the markup (RFC-0003). The islands are collected from the lowered program's
// `islandOpen` ops; the cell values + island scope come from `arena`; the serializer filters to the
// island-scope allowlist and scriptJSON-escapes the payload.

extension HTML {
    /// Render to HTML bytes followed by `<script type="application/adh-state+json" id="adh-state">…`
    /// carrying this render's island-scoped reactive state, ready for the client runtime to resume.
    public consuming func renderHydratable(arena: CellArena) throws(WireError) -> [UInt8] {
        var program = HTMLProgram()
        Self._render(self, into: &program)

        var islands: [WireIsland] = []
        for op in program.ops {
            if case .islandOpen(let id, let on, let scope) = op {
                islands.append(WireIsland(id: id, on: on, scope: scope))
            }
        }

        var sink = ArraySink(reservingCapacity: program.ops.count * 16)
        Renderer.render(program, into: &sink)

        let state = try WireSerializer.scriptBytes(cells: arena.cells, islands: islands)
        var out = sink.bytes
        out.append(contentsOf: Self.scriptOpen)
        out.append(contentsOf: state)
        out.append(contentsOf: Self.scriptClose)
        return out
    }

    private static var scriptOpen: [UInt8] {
        Array(#"<script type="application/adh-state+json" id="adh-state">"#.utf8)
    }
    private static var scriptClose: [UInt8] { Array("</script>".utf8) }
}
