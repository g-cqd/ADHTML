internal import ADJSONCore
internal import OrderedCollections

// Serializes a render's reactive-cell graph + islands into the hydration wire format v1:
// `{"v":1,"cells":[…],"islands":[…]}` (RFC-0003 / ADR-0007). Two invariants make this simple and
// recursion-free:
//   • Cells are emitted in CREATION order, which is a TOPOLOGICAL order — a computed can only read
//     cells created before it — so the dependency graph is a DAG (no cycles to break) and a dependency
//     is just an earlier index.
//   • Only cells reachable from a declared island's `scope` are serialized (the data-leak guard,
//     RFC-0003 §6): a non-island cell never reaches the client.
// Reachability is an explicit-worklist closure; emission is a flat loop; JSON is produced by ADJSON
// and escaped for the inline `<script>` by `Escaper.escapeScriptJSON`.

/// Serializes the reactive-cell graph + islands to the hydration wire format.
public enum WireSerializer {
    /// Encode the wire payload to JSON bytes, escaped for safe embedding in the inline state script.
    /// Reuses ADJSON's HTML-safe encoder (`escapeHTMLUnsafe`), which escapes `<`/`>`/`&` and
    /// U+2028/U+2029 to `\uXXXX` *during* encoding — one SWAR-accelerated pass, no separate escape pass
    /// and no duplicated escaper (ADR-0011 reuse). The result still parses as the same JSON value, so
    /// the wire format is unchanged; `</script>` simply cannot appear literally.
    public static func scriptBytes(
        cells: [CellArena.Cell], islands: [WireIsland]
    ) throws(WireError) -> [UInt8] {
        do {
            return try payload(cells: cells, islands: islands)
                .encodedBytes(options: JSONEncodingOptions(escapeHTMLUnsafe: true))
        } catch {
            throw WireError.encoding("\(error)")
        }
    }

    /// Build the wire payload as a `JSONValue` (internal; `scriptBytes` is the public entry).
    static func payload(cells: [CellArena.Cell], islands: [WireIsland]) -> JSONValue {
        let reachable = reachableCells(cells: cells, islands: islands)
        let oldToNew = reindex(cellCount: cells.count, reachable: reachable)

        var cellsJSON: [JSONValue] = []
        cellsJSON.reserveCapacity(oldToNew.count)
        for index in 0 ..< cells.count where reachable.contains(index) {
            cellsJSON.append(encodeCell(cells[index], oldToNew: oldToNew))
        }

        var islandsJSON: [JSONValue] = []
        islandsJSON.reserveCapacity(islands.count)
        for island in islands {
            islandsJSON.append(encodeIsland(island, oldToNew: oldToNew))
        }

        var root = OrderedDictionary<String, JSONValue>()
        root["v"] = .int(Int64(ADHTMLCore.wireFormatVersion))
        root["cells"] = .array(cellsJSON)
        root["islands"] = .array(islandsJSON)
        return .object(root)
    }

    // MARK: - The island-scope allowlist (explicit worklist, no recursion)

    private static func reachableCells(cells: [CellArena.Cell], islands: [WireIsland]) -> Set<Int> {
        var reachable = Set<Int>()
        var worklist: [Int] = []
        for island in islands {
            for seed in island.scope { worklist.append(Int(seed.raw)) }
        }
        while let index = worklist.popLast() {
            guard index >= 0, index < cells.count, reachable.insert(index).inserted else { continue }
            if case .computed(let dependencies) = cells[index].kind {
                for dependency in dependencies { worklist.append(Int(dependency.raw)) }
            }
        }
        return reachable
    }

    /// Map each reachable old index to its compacted new index, in creation order.
    private static func reindex(cellCount: Int, reachable: Set<Int>) -> [Int: Int] {
        var oldToNew: [Int: Int] = [:]
        var next = 0
        for index in 0 ..< cellCount where reachable.contains(index) {
            oldToNew[index] = next
            next += 1
        }
        return oldToNew
    }

    // MARK: - Encoding

    private static func encodeCell(_ cell: CellArena.Cell, oldToNew: [Int: Int]) -> JSONValue {
        var object = OrderedDictionary<String, JSONValue>()
        switch cell.kind {
            case .signal:
                object["$"] = .string("sig")
                object["v"] = json(cell.value)
            case .computed(let dependencies):
                object["$"] = .string("cmp")
                object["d"] = .array(remap(dependencies, oldToNew))
                object["v"] = json(cell.value)
        }
        return .object(object)
    }

    private static func encodeIsland(_ island: WireIsland, oldToNew: [Int: Int]) -> JSONValue {
        var object = OrderedDictionary<String, JSONValue>()
        object["id"] = .string(island.id.raw)
        object["on"] = .string(island.on.attributeValue)
        object["scope"] = .array(remap(island.scope, oldToNew))
        return .object(object)
    }

    private static func remap(_ ids: [CellID], _ oldToNew: [Int: Int]) -> [JSONValue] {
        ids.compactMap { oldToNew[Int($0.raw)] }.map { .int(Int64($0)) }
    }

    /// Bridge a (shallow) cell value to ADJSON's `JSONValue`. Bounded by the value's own nesting.
    private static func json(_ value: WireValue) -> JSONValue {
        switch value {
            case .null: .null
            case .bool(let bool): .bool(bool)
            case .int(let int): .int(int)
            case .double(let double): .number(double)
            case .string(let string): .string(string)
            case .array(let array): .array(array.map(json))
        }
    }
}
