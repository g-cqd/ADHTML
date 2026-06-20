import Foundation
import PackagePlugin

// The Swift-side generator for the shared wire-attribute vocabulary. `wire-tokens.json` (repo root) is the
// single source of truth; this command plugin regenerates BOTH the renderer's constants
// (`Sources/ADHTMLCore/Wire/WireTokens.swift`) and the runtime's constants (`ClientRuntime/src/tokens.js`),
// so the two can never drift. Run:
//
//     swift package --allow-writing-to-package-directory generate-wire-tokens
//
// A Swift parity test (`WireTokensTests`) and a JS parity test re-derive from `wire-tokens.json`, so a
// stale generated file fails CI. Generation lives on the Swift side (this plugin), not in a JS script.
@main
struct GenerateWireTokens: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let root = context.package.directoryURL
        let data = try Data(contentsOf: root.appending(path: "wire-tokens.json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawPairs = object["tokens"] as? [[String]]
        else {
            Diagnostics.error(#"wire-tokens.json: expected { "tokens": [[name, token], …] }"#)
            return
        }
        let pairs = rawPairs.compactMap { $0.count == 2 ? (name: $0[0], token: $0[1]) : nil }

        try Self.swiftSource(pairs)
            .write(
                to: root.appending(path: "Sources/ADHTMLCore/Wire/WireTokens.swift"),
                atomically: true, encoding: .utf8)
        try Self.jsSource(pairs)
            .write(
                to: root.appending(path: "ClientRuntime/src/tokens.js"),
                atomically: true, encoding: .utf8)

        print("generate-wire-tokens: wrote \(pairs.count) tokens → WireTokens.swift + ClientRuntime/src/tokens.js")
    }

    /// Swift identifiers that collide with keywords need backtick-escaping in the generated `static let`.
    private static let swiftKeywords: Set<String> = [
        "if", "in", "for", "class", "case", "default", "where", "let", "var", "as", "is", "switch", "func"
    ]

    private static func banner(_ other: String) -> String {
        "// GENERATED from wire-tokens.json by `swift package generate-wire-tokens` — DO NOT EDIT.\n"
            + "// The closed wire-attribute vocabulary, shared with \(other) (parity-tested). 1-char base36 tokens.\n"
    }

    static func swiftSource(_ pairs: [(name: String, token: String)]) -> String {
        var out = banner("ClientRuntime/src/tokens.js")
        out +=
            "\n/// The closed set of ADHTML wire attribute tokens (RFC-0021 / ADR-0007), shared with the JS runtime.\n"
        out += "public enum WireToken {\n"
        for pair in pairs {
            let name = swiftKeywords.contains(pair.name) ? "`\(pair.name)`" : pair.name
            out += "    public static let \(name) = \"\(pair.token)\"\n"
        }
        out += "\n    /// Every (name, token) pair — the input to the Swift↔JS parity test.\n"
        // No trailing comma on the last element (`.swift-format` forbids it in multi-line collections).
        out += "    public static let all: [(name: String, token: String)] = [\n"
        out += pairs.map { "        (\"\($0.name)\", \"\($0.token)\")" }.joined(separator: ",\n")
        out += "\n    ]\n}\n"
        return out
    }

    static func jsSource(_ pairs: [(name: String, token: String)]) -> String {
        var out = banner("Sources/ADHTMLCore/Wire/WireTokens.swift")
        // A plain object literal (no `Object.freeze` — that reads as a side effect and would keep this
        // module from tree-shaking after build.js inlines every `T.<name>` to its literal).
        out += "\nexport const T = {\n"
        for pair in pairs { out += "  \(pair.name): \"\(pair.token)\",\n" }
        out += "};\n"
        return out
    }
}
