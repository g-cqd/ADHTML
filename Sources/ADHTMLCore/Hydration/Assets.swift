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

/// Accumulates a render's component-scoped assets, DEDUPED by scope hash (two instances of one component
/// type contribute one `<style>`). `Mutex`-guarded so a streaming/async render is data-race-free; `nil` on
/// the static `render()` path (no injection point), mirroring how ``CellArena`` is absent there.
public final class AssetSink: Sendable {
    /// One deduped asset entry: the scope hash (its `data-scope` value) + the rendered CSS bytes.
    public struct Entry: Sendable, Equatable {
        public let scope: String
        public let css: [UInt8]
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

    /// The deduped `<style>…</style>` block for all recorded CSS, or empty when none — injected verbatim
    /// (already scoped + escape-free; CSS is trusted `StaticString`). The gated bridge re-emits with a nonce.
    public func styleTag() -> [UInt8] {
        let all = entries
        guard !all.isEmpty else { return [] }
        var out = Array("<style>".utf8)
        for entry in all { out.append(contentsOf: entry.css) }
        out.append(contentsOf: Array("</style>".utf8))
        return out
    }
}

/// Records a component type's style into the ambient ``AssetSink`` and computes its `data-scope` hash.
enum ComponentAssets {
    /// Hash the type name + CSS (so two types with identical CSS still scope distinctly), dedup-record the
    /// scoped/global CSS into `sink`, and return the base36 scope hash (the `data-scope` value).
    static func record(style: ScopedStyle, typeName: String, into sink: AssetSink) -> String {
        let cssBytes = style.css.withUTF8Buffer { unsafe Array($0) }
        var keyBytes = Array(typeName.utf8)
        keyBytes.append(contentsOf: cssBytes)
        let scope = base36(XXH64.hash(keyBytes))

        // Dedup BEFORE scoping: a repeated instance of the same type skips the (otherwise wasted) scope pass.
        guard !sink.contains(scope) else { return scope }

        let rendered: [UInt8]
        switch style.mode {
            case .scoped, .shadow: rendered = CSSScoper.scope(cssBytes, scope: scope)
            case .global: rendered = cssBytes
        }
        sink.record(AssetSink.Entry(scope: scope, css: rendered))
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
