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

    /// Build the wire payload as a `JSONValue` (internal; `scriptBytes` is the public entry). Throws if a
    /// cell value's array nesting exceeds the serializer's depth cap (failure-safe, never a stack crash).
    static func payload(cells: [CellArena.Cell], islands: [WireIsland]) throws(WireError) -> JSONValue {
        let reachable = reachableCells(cells: cells, islands: islands)
        let oldToNew = reindex(cellCount: cells.count, reachable: reachable)

        var cellsJSON: [JSONValue] = []
        cellsJSON.reserveCapacity(oldToNew.count)
        for index in 0 ..< cells.count where reachable.contains(index) {
            cellsJSON.append(try encodeCell(cells[index], oldToNew: oldToNew))
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
            if case .computed(let dependencies, _) = cells[index].kind {
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

    private static func encodeCell(
        _ cell: CellArena.Cell, oldToNew: [Int: Int]
    ) throws(WireError) -> JSONValue {
        var object = OrderedDictionary<String, JSONValue>()
        switch cell.kind {
            case .signal:
                object["$"] = .string("sig")
                object["v"] = try json(cell.value)
            case .computed(let dependencies, let expr):
                object["$"] = .string("cmp")
                object["d"] = .array(remap(dependencies, oldToNew))
                object["v"] = try json(cell.value)
                if let expr { object["e"] = try encodeExpr(expr, oldToNew: oldToNew) }
        }
        return .object(object)
    }

    /// Serialize a client-recomputable `WireExpr` to compact JSON, reindexing its cell refs (old → new)
    /// like `d`. Iterative post-order (no recursion, ADR-0002) under the same `maxValueDepth` cap.
    /// Encoding: cell `{"c":idx}`, literals `{"i"|"d"|"b"|"s": …}`, binary `{"o":op,"l":…,"r":…}`.
    private static func encodeExpr(_ root: WireExpr, oldToNew: [Int: Int]) throws(WireError) -> JSONValue {
        enum Work {
            case visit(WireExpr)
            case fold(BinaryOp)
        }
        var work: [Work] = [.visit(root)]
        var values: [JSONValue] = []
        while let item = work.popLast() {
            if work.count > Self.maxValueDepth {
                throw WireError.encoding("wire expression nesting exceeds \(Self.maxValueDepth)")
            }
            switch item {
                case .visit(.binary(let op, let lhs, let rhs)):
                    work.append(.fold(op))
                    work.append(.visit(rhs))
                    work.append(.visit(lhs))
                case .visit(let leaf):
                    values.append(exprLeaf(leaf, oldToNew: oldToNew))
                case .fold(let op):
                    let rhs = values.removeLast()
                    let lhs = values.removeLast()
                    var node = OrderedDictionary<String, JSONValue>()
                    node["o"] = .string(op.rawValue)
                    node["l"] = lhs
                    node["r"] = rhs
                    values.append(.object(node))
            }
        }
        return values.removeLast()
    }

    /// A leaf `WireExpr` (cell ref or literal) as compact JSON; cell refs are reindexed.
    private static func exprLeaf(_ expr: WireExpr, oldToNew: [Int: Int]) -> JSONValue {
        var node = OrderedDictionary<String, JSONValue>()
        switch expr {
            case .cell(let id): node["c"] = .int(Int64(oldToNew[Int(id.raw)] ?? Int(id.raw)))
            case .int(let value): node["i"] = .int(value)
            case .double(let value): node["d"] = .number(value)
            case .bool(let value): node["b"] = .bool(value)
            case .string(let value): node["s"] = .string(value)
            case .binary: break  // handled by encodeExpr's fold; never reached here
        }
        return .object(node)
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

    /// The deepest `WireValue` array nesting the serializer will encode. A value past this throws (a
    /// failure-safe ceiling) instead of risking a deep walk — the array nesting is author-bounded, so
    /// this is generous; the cap exists only so adversarial/buggy input can never run away.
    static let maxValueDepth = 64

    /// Bridge a cell value to ADJSON's `JSONValue`. Scalars convert directly (the overwhelming common
    /// case); nested arrays are converted with an **explicit stack** (no recursion, ADR-0002) and a
    /// depth cap. Post-order: a frame collects its converted children, then folds to a `.array` and
    /// hands it to its parent.
    private static func json(_ value: WireValue) throws(WireError) -> JSONValue {
        if let leaf = scalarJSON(value) { return leaf }
        guard case .array(let rootElements) = value else { return .null }  // unreachable: non-scalar = array

        struct Frame {
            let elements: [WireValue]
            var index = 0
            var built: [JSONValue] = []
        }
        var stack: [Frame] = [Frame(elements: rootElements)]
        var result: JSONValue = .array([])

        while let top = stack.indices.last {
            if stack.count > Self.maxValueDepth {
                throw WireError.encoding("wire value array nesting exceeds \(Self.maxValueDepth)")
            }
            if stack[top].index == stack[top].elements.count {
                let folded = JSONValue.array(stack[top].built)
                stack.removeLast()
                if stack.isEmpty { result = folded } else { stack[stack.count - 1].built.append(folded) }
                continue
            }
            let child = stack[top].elements[stack[top].index]
            stack[top].index += 1
            if let leaf = scalarJSON(child) {
                stack[top].built.append(leaf)
            } else if case .array(let childElements) = child {
                stack.append(Frame(elements: childElements))
            }
        }
        return result
    }

    /// A scalar `WireValue` as a `JSONValue`, or `nil` for `.array` (handled by the iterative folder).
    private static func scalarJSON(_ value: WireValue) -> JSONValue? {
        switch value {
            case .null: .null
            case .bool(let bool): .bool(bool)
            case .int(let int): .int(int)
            case .double(let double): .number(double)
            case .string(let string): .string(string)
            case .array: nil
        }
    }
}
