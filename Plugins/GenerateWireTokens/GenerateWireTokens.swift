import Foundation
import PackagePlugin

// The Swift-side generator for the shared wire vocabulary. `wire-tokens.json` (repo root) is the single
// source of truth; this command plugin regenerates BOTH the renderer's constants
// (`Sources/ADHTMLCore/Wire/WireTokens.swift`) and the runtime's constants (`ClientRuntime/src/tokens.js`),
// so the two can never drift. It covers three closed categories — attribute names (`WireToken` / `T`),
// behavior names (`WireBehavior` / `B`), and Action swap modes (`WireSwap` / `S`). Run:
//
//     swift package --allow-writing-to-package-directory generate-wire-tokens
//
// Parity tests on both sides re-derive from the JSON, so a stale generated file fails CI. Generation lives
// on the Swift side (this plugin), not in a JS script.
@main
struct GenerateWireTokens: CommandPlugin {
    /// (spec key, Swift enum, JS const, prefix) per closed category. The `tokens` (attribute NAME) category
    /// gets the `data-` prefix here — the one place it is applied — so the spec stays bare and the wire is
    /// valid HTML5 custom data attributes. Behaviors/swaps are attribute VALUES, so they stay bare.
    private static let categories = [
        (key: "tokens", swiftEnum: "WireToken", jsConst: "T", prefix: "data-"),
        (key: "behaviors", swiftEnum: "WireBehavior", jsConst: "B", prefix: ""),
        (key: "swaps", swiftEnum: "WireSwap", jsConst: "S", prefix: "")
    ]

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let root = context.package.directoryURL
        let data = try Data(contentsOf: root.appending(path: "wire-tokens.json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Diagnostics.error("wire-tokens.json: not a JSON object")
            return
        }
        func pairs(_ key: String, prefix: String) -> [(name: String, token: String)] {
            (object[key] as? [[String]] ?? [])
                .compactMap {
                    $0.count == 2 ? (name: $0[0], token: prefix + $0[1]) : nil
                }
        }

        var swift = Self.banner("ClientRuntime/src/tokens.js")
        var js = Self.banner("Sources/ADHTMLCore/Wire/WireTokens.swift")
        var total = 0
        for category in Self.categories {
            let group = pairs(category.key, prefix: category.prefix)
            total += group.count
            swift += Self.swiftEnum(category.swiftEnum, group)
            js += Self.jsMap(category.jsConst, group)
        }

        try swift.write(
            to: root.appending(path: "Sources/ADHTMLCore/Wire/WireTokens.swift"),
            atomically: true, encoding: .utf8)
        try js.write(
            to: root.appending(path: "ClientRuntime/src/tokens.js"),
            atomically: true, encoding: .utf8)
        print("generate-wire-tokens: wrote \(total) tokens → WireTokens.swift + ClientRuntime/src/tokens.js")
    }

    /// Swift identifiers that collide with keywords need backtick-escaping in the generated `static let`.
    private static let swiftKeywords: Set<String> = [
        "if", "in", "for", "class", "case", "default", "where", "let", "var", "as", "is", "switch", "func"
    ]

    private static func banner(_ other: String) -> String {
        "// GENERATED from wire-tokens.json by `swift package generate-wire-tokens` — DO NOT EDIT.\n"
            + "// The closed wire vocabulary (attributes/behaviors/swaps), shared with \(other) "
            + "(parity-tested). 1-char base36 tokens.\n"
    }

    private static func swiftEnum(_ name: String, _ pairs: [(name: String, token: String)]) -> String {
        var out =
            "\n/// Generated wire tokens — shared with the JS runtime; do not edit by hand.\npublic enum \(name) {\n"
        for pair in pairs {
            let identifier = swiftKeywords.contains(pair.name) ? "`\(pair.name)`" : pair.name
            out += "    public static let \(identifier) = \"\(pair.token)\"\n"
        }
        out += "\n    /// Every (name, token) pair — the input to the Swift↔JS parity test.\n"
        // No trailing comma on the last element (`.swift-format` forbids it in multi-line collections).
        out += "    public static let all: [(name: String, token: String)] = [\n"
        out += pairs.map { "        (\"\($0.name)\", \"\($0.token)\")" }.joined(separator: ",\n")
        out += "\n    ]\n}\n"
        return out
    }

    private static func jsMap(_ name: String, _ pairs: [(name: String, token: String)]) -> String {
        // Plain object literals (no `Object.freeze` — that reads as a side effect and would keep this module
        // from tree-shaking after build.js inlines every `\(name).<key>` to its literal).
        var out = "\nexport const \(name) = {\n"
        for pair in pairs { out += "  \(pair.name): \"\(pair.token)\",\n" }
        out += "};\n"
        return out
    }
}
