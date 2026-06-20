// Generate the shared wire-attribute token constants for BOTH languages from `wire-tokens.json` (the
// single source of truth), so the Swift renderer and the JS runtime cannot drift. Writes:
//   • ClientRuntime/src/tokens.js     — `export const T = { … }` (the JS runtime imports it)
//   • Sources/ADHTMLCore/Wire/WireTokens.swift — `enum WireToken { static let … }` (the renderer uses it)
// Run directly (`bun gen-tokens.js`) or via build.js (which runs it first). A Swift + a JS parity test
// re-derive from the JSON, so a stale generated file fails CI.

const spec = await Bun.file(new URL("../wire-tokens.json", import.meta.url)).json();
const tokens = spec.tokens;
const entries = Object.entries(tokens);

// Swift keywords used as token names need backtick-escaping in the generated `static let`.
const SWIFT_KEYWORDS = new Set(["if", "in", "for", "class", "case", "default", "where", "let", "var", "as", "is"]);
const swiftName = (name) => (SWIFT_KEYWORDS.has(name) ? `\`${name}\`` : name);

const banner = (tool) =>
  `// GENERATED from wire-tokens.json by ClientRuntime/gen-tokens.js — DO NOT EDIT.\n` +
  `// The closed wire-attribute vocabulary, shared with ${tool} (parity-tested). Short htmx-style 'a-' prefix.\n`;

// --- JS ---
const js =
  banner("Sources/ADHTMLCore/Wire/WireTokens.swift") +
  `\nexport const T = Object.freeze({\n` +
  entries.map(([name, token]) => `  ${name}: ${JSON.stringify(token)},`).join("\n") +
  `\n});\n`;
await Bun.write(new URL("./src/tokens.js", import.meta.url), js);

// --- Swift ---
const swift =
  banner("ClientRuntime/src/tokens.js") +
  `\n/// The closed set of ADHTML wire attribute tokens (RFC-0021 / ADR-0007), shared with the JS runtime.\n` +
  `public enum WireToken {\n` +
  entries.map(([name, token]) => `    public static let ${swiftName(name)} = ${JSON.stringify(token)}`).join("\n") +
  `\n\n    /// Every (name, token) pair — the input to the Swift↔JS parity test.\n` +
  `    public static let all: [(name: String, token: String)] = [\n` +
  entries.map(([name, token]) => `        (${JSON.stringify(name)}, ${JSON.stringify(token)}),`).join("\n") +
  `\n    ]\n}\n`;
await Bun.write(new URL("../Sources/ADHTMLCore/Wire/WireTokens.swift", import.meta.url), swift);

console.log(`gen-tokens: wrote ${entries.length} tokens -> src/tokens.js + Sources/ADHTMLCore/Wire/WireTokens.swift`);
