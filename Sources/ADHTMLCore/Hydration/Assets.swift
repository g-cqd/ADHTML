internal import ADFCore
private import Synchronization

// Component-scoped assets (Track 4) — an ADDITIVE escape hatch for a genuinely bespoke widget, NOT a
// replacement for the P1–P9 declarative vocabulary. A `Component` co-locates a `ScopedStyle` (and, with
// the gated bridge, a `Script`); the engine scopes the CSS, dedups it by a per-type hash, stamps a mount
// root (`data-component`/`data-scope`), and `renderHydratable` injects one deduped `<style>` before the
// inline state script. The component `body` stays the source of truth + the no-JS fallback; the asset only
// ENHANCES. Every asset value is a `StaticString` (trusted, never user-interpolated), so no user data can
// reach a `<style>`/`<script>` body — the core surface is Foundation-free, I/O-free, and nonce-free (the
// gated `ADHTMLAssets` bridge stamps the CSP nonce + serves modules).

/// A component's co-located CSS. `.scoped` (the default) confines every selector under the component's
/// `data-scope` ancestor (``CSSScoper``); `.global` injects it verbatim; `.shadow` is reserved for
/// declarative shadow DOM (rendered scoped until that lands). Named `ScopedStyle` to avoid the `Stylesheet`
/// head helper.
public struct ScopedStyle: Sendable {
    public enum Mode: Sendable, Equatable {
        /// Confine the CSS to the declaring component (the default — selectors gain a `data-scope` ancestor).
        case scoped
        /// Inject the CSS verbatim (page-global); the author owns specificity.
        case global
        /// Reserved for declarative shadow DOM; currently rendered like `.scoped`.
        case shadow
    }

    public let css: StaticString
    public let mode: Mode

    public init(_ css: StaticString, _ mode: Mode = .scoped) {
        self.css = css
        self.mode = mode
    }
}

/// A component's co-located JavaScript (Track 4). `.inline` is emitted as a CSP-nonced `<script>` in the
/// page; `.module(name:)` names a content-hashed, SRI-served ES module the gated bridge loads. Both are
/// `StaticString` (trusted, never user-interpolated). The script ENHANCES — it registers `ADH.mount(name,
/// fn)` whose only network primitive is `ctx.action` (the signed RFC-0019 endpoint), so it never
/// re-implements the model; the component `body` stays the no-JS fallback.
public enum Script: Sendable {
    /// Inline JavaScript, emitted as a nonced `<script>` (no SRI — it is part of the HTML, covered by CSP).
    case inline(StaticString)
    /// A named ES module (bundled + content-hashed + SRI-served by the gated `ADHTMLAssets` bridge).
    case module(name: StaticString)

    /// The bytes that distinguish this script in the per-type asset hash (so a script-only component, or
    /// two same-CSS components with different scripts, still scope distinctly).
    var identityBytes: [UInt8] {
        switch self {
            case .inline(let js): return js.withUTF8Buffer { unsafe Array($0) }
            case .module(let name): return name.withUTF8Buffer { unsafe Array($0) }
        }
    }
}

/// Accumulates a render's component-scoped assets, DEDUPED by scope hash (two instances of one component
/// type contribute one `<style>`). `Mutex`-guarded so a streaming/async render is data-race-free; `nil` on
/// the static `render()` path (no injection point), mirroring how ``CellArena`` is absent there.
public final class AssetSink: Sendable {
    /// One deduped asset entry for a component type: the scope hash (its `data-scope` value), the rendered
    /// CSS bytes (empty when none), the inline-script bytes (empty when none), and the module name (the
    /// gated bridge loads it as a content-hashed, SRI-served `<script type=module>`).
    public struct Entry: Sendable, Equatable {
        public let scope: String
        public let css: [UInt8]
        public let inlineScript: [UInt8]
        public let module: String?
    }

    private struct State {
        var order: [String] = []
        var byScope: [String: Entry] = [:]
    }
    private let state = Mutex(State())

    public init() {}

    /// Record an entry the first time its scope hash is seen (later duplicates are dropped).
    func record(_ entry: Entry) {
        state.withLock { state in
            if state.byScope[entry.scope] == nil {
                state.byScope[entry.scope] = entry
                state.order.append(entry.scope)
            }
        }
    }

    /// Whether an entry for `scope` is already recorded — lets a repeated instance skip re-scoping its CSS.
    func contains(_ scope: String) -> Bool { state.withLock { $0.byScope[scope] != nil } }

    /// The deduped entries in first-seen order — deterministic output.
    public var entries: [Entry] {
        state.withLock { state in state.order.compactMap { state.byScope[$0] } }
    }

    /// The deduped `<style>…</style>` block for all recorded CSS, or empty when none — the CSS is verbatim
    /// (already scoped + escape-free; trusted `StaticString`). `nonce` (the gated bridge's `CSPNonceKey`
    /// value) is stamped on the tag for a strict CSP; `nil` keeps it nonce-free.
    public func styleTag(nonce: String? = nil) -> [UInt8] {
        let css = entries.flatMap(\.css)
        guard !css.isEmpty else { return [] }
        var out = Self.openingTag("<style", nonce: nonce)
        out.append(contentsOf: css)
        out.append(contentsOf: Array("</style>".utf8))
        return out
    }

    /// The deduped inline `<script>…</script>` blocks for all recorded `.inline` scripts (one per type), or
    /// empty when none. Trusted `StaticString` (escape-free). `nonce` is stamped for a strict CSP; `.module`
    /// scripts are served separately (this covers only inline JS).
    public func scriptTag(nonce: String? = nil) -> [UInt8] {
        var out: [UInt8] = []
        for entry in entries where !entry.inlineScript.isEmpty {
            out.append(contentsOf: Self.openingTag("<script", nonce: nonce))
            out.append(contentsOf: entry.inlineScript)
            out.append(contentsOf: Array("</script>".utf8))
        }
        return out
    }

    /// `<style` / `<script` with an optional escaped `nonce="…"`, closed with `>`. The nonce routes through
    /// the attribute escaper (defense-in-depth; a CSP nonce is hex/base64, already attribute-safe).
    private static func openingTag(_ tag: StaticString, nonce: String?) -> [UInt8] {
        var out = tag.withUTF8Buffer { unsafe Array($0) }
        if let nonce {
            out.append(contentsOf: Array(" nonce=\"".utf8))
            var sink = ArraySink()
            Escaper.write(nonce, context: .attribute, into: &sink)
            out.append(contentsOf: sink.bytes)
            out.append(0x22)  // closing quote
        }
        out.append(0x3E)  // >
        return out
    }
}

/// Records a component type's style + script into the ambient ``AssetSink`` and computes its `data-scope`
/// hash (the `data-component`/`data-scope` mount-root values).
enum ComponentAssets {
    /// Hash the type name + CSS + script identity (so a script-only component, or two same-CSS components
    /// with different scripts, still scope distinctly), dedup-record the scoped CSS + inline script into
    /// `sink`, and return the base36 scope hash.
    static func record(style: ScopedStyle?, script: Script?, typeName: String, into sink: AssetSink) -> String {
        let cssBytes = style.map { $0.css.withUTF8Buffer { unsafe Array($0) } } ?? []
        var keyBytes = Array(typeName.utf8)
        keyBytes.append(contentsOf: cssBytes)
        if let script { keyBytes.append(contentsOf: script.identityBytes) }
        let scope = base36(XXH64.hash(keyBytes))

        // Dedup BEFORE scoping: a repeated instance of the same type skips the (otherwise wasted) scope pass.
        guard !sink.contains(scope) else { return scope }

        let renderedCSS: [UInt8]
        switch style?.mode {
            case .scoped, .shadow: renderedCSS = CSSScoper.scope(cssBytes, scope: scope)
            case .global: renderedCSS = cssBytes
            case .none: renderedCSS = []
        }

        var inlineScript: [UInt8] = []
        var module: String?
        switch script {
            case .inline(let js): inlineScript = js.withUTF8Buffer { unsafe Array($0) }
            case .module(let name): module = name.withUTF8Buffer { String(decoding: unsafe Array($0), as: UTF8.self) }
            case .none: break
        }
        sink.record(AssetSink.Entry(scope: scope, css: renderedCSS, inlineScript: inlineScript, module: module))
        return scope
    }
}

/// A `UInt64` as lowercase base36 — the compact `data-scope` hash (matches the wire-token alphabet).
func base36(_ value: UInt64) -> String {
    guard value != 0 else { return "0" }
    let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz".utf8)
    var remaining = value
    var out: [UInt8] = []
    while remaining > 0 {
        out.append(digits[Int(remaining % 36)])
        remaining /= 36
    }
    return String(decoding: out.reversed(), as: UTF8.self)
}
