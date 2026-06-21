public import ADHTMLCore
public import ADServeCore
// ADHTMLAssets (gated `ADHTML_ASSETS`) — the component-scoped-asset SERVING bridge (Track 4, ADR-0021).
// The core (ADHTMLCore) already scopes the CSS, records `.module` component names in the render's
// `AssetSink`, and injects the deduped `<style>` + inline `<script>`s (nonce-stamped when a nonce is
// supplied). This gated bridge adds the two things the core can't: it LOADS the bun-produced
// `manifest.json` (I/O) and APPENDS a content-hashed, SRI-pinned `<script type=module src integrity nonce>`
// for each `.module` component on the page. SRI is computed at BUILD time by bun (parity-pinned to
// `ADHTMLSRI` by the ClientRuntime test), so the bridge TRUSTS the manifest's integrity — it never
// recomputes server-side, and pulls no swift-crypto. Serve the modules with ADServe `Static("/assets",
// root:)`; mint the nonce with the `CSPNonce` middleware and read it from `ctx.storage[CSPNonceKey.self]`.
internal import Foundation

/// The component-asset manifest produced by `ClientRuntime/build-components.js`: `name → {file, integrity,
/// bytes}`. The bridge resolves a page's `.module` component names against it to emit the served-module
/// script tags.
public struct AssetManifest: Sendable, Equatable {
    /// One bundled, content-hashed, SRI-pinned module.
    public struct Module: Sendable, Equatable, Codable {
        /// The content-hashed filename under the asset path (e.g. `counter.a9285af9d50f9145.js`).
        public let file: String
        /// The Subresource Integrity token (`sha256-<base64>`), parity-pinned to `ADHTMLSRI`.
        public let integrity: String
        /// The bundled byte size.
        public let bytes: Int

        public init(file: String, integrity: String, bytes: Int) {
            self.file = file
            self.integrity = integrity
            self.bytes = bytes
        }
    }

    public let modules: [String: Module]

    public init(modules: [String: Module]) { self.modules = modules }

    /// Decode a manifest from `manifest.json` bytes (the bun build output).
    public init(json: [UInt8]) throws {
        self.modules = try JSONDecoder().decode([String: Module].self, from: Data(json))
    }

    /// Load + decode `manifest.json` from disk (the handler's one-time setup, not per request).
    public init(contentsOfFile path: String) throws {
        try self.init(json: Array(Data(contentsOf: URL(fileURLWithPath: path))))
    }
}

extension ResponseContent {
    /// Render a hydratable ADHTML view to a buffered `text/html` response, stamping `nonce` on the injected
    /// `<style>`/inline-`<script>`s and APPENDING a content-hashed, SRI-pinned `<script type=module src
    /// integrity nonce>` for each `.module` component on the page (resolved from `manifest`). The component
    /// `body` stays the no-JS fallback; the modules ENHANCE.
    ///
    /// Wiring: install the `CSPNonce` middleware on the route, read `ctx.storage[CSPNonceKey.self]` for the
    /// `nonce`, and serve the bundles with `Static(assetPath, root: <assets dir>)`.
    public static func adhtmlAssets(
        _ view: consuming some HTML,
        manifest: AssetManifest,
        arena: CellArena = CellArena(),
        nonce: String? = nil,
        assetPath: String = "/assets"
    ) throws(WireError) -> ResponseContent {
        let assets = AssetSink()
        var bytes = try view.renderHydratable(arena: arena, nonce: nonce, assets: assets)
        bytes.append(
            contentsOf: ADHTMLAssets.moduleScriptTags(
                for: assets, manifest: manifest, nonce: nonce, basePath: assetPath))
        return .html(bytes)
    }
}

/// The component-scoped-asset serving helpers (the injection the gated bridge owns).
public enum ADHTMLAssets {
    /// `<script type="module" src integrity nonce>` for each `.module` component recorded in `assets`,
    /// skipping any whose name is absent from `manifest` (graceful — a missing module just isn't served).
    /// Every attribute value routes through the engine's attribute escaper. Module scripts are `defer`red by
    /// the browser, so appending them after the inline state script is correct (the mount bridge late-mounts).
    public static func moduleScriptTags(
        for assets: AssetSink, manifest: AssetManifest, nonce: String?, basePath: String
    ) -> [UInt8] {
        var out: [UInt8] = []
        for entry in assets.entries {
            guard let name = entry.module, let module = manifest.modules[name] else { continue }
            out.append(contentsOf: Array(#"<script type="module""#.utf8))
            appendAttribute(&out, "src", "\(basePath)/\(module.file)")
            appendAttribute(&out, "integrity", module.integrity)
            if let nonce { appendAttribute(&out, "nonce", nonce) }
            out.append(contentsOf: Array("></script>".utf8))
        }
        return out
    }

    /// Append ` name="<escaped value>"` to `out` via the engine's attribute escaper.
    private static func appendAttribute(_ out: inout [UInt8], _ name: String, _ value: String) {
        out.append(contentsOf: Array(" \(name)=\"".utf8))
        var sink = ArraySink()
        Escaper.write(value, context: .attribute, into: &sink)
        out.append(contentsOf: sink.bytes)
        out.append(0x22)  // closing quote
    }
}
