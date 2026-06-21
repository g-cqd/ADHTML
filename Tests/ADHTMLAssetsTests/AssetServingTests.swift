import ADHTMLCore  // Component / div / CellArena / AssetSink / renderHydratable (MemberImportVisibility)
import ADServeCore  // ResponseContent
import Testing

@testable import ADHTMLAssets

// The gated component-scoped-asset serving bridge (Track 4 A3 / ADR-0021): the manifest model, the
// nonce-stamped `<style>`/inline-`<script>` injection (core, exercised here through the gated target), and
// the served-module `<script type=module src integrity nonce>` tags. Pure render + byte assertions — no
// running server (the live loopback proof is the NIO/Playwright e2e).

// A component served by a bundled ES module (no inline JS, no CSS).
private struct ModuleWidget: Component {
    static var script: Script? { .module(name: "counter") }
    var body: some HTML { div { "0" } }
}

// A component with scoped CSS + an inline mount script — exercises the nonce stamping.
private struct InlineWidget: Component {
    static var style: ScopedStyle? { ScopedStyle(".a { color: blue }") }
    static var script: Script? { .inline("console.log(1)") }
    var body: some HTML { div { "y" }.class("a") }
}

struct AssetServingTests {
    private static let manifest = AssetManifest(modules: [
        "counter": .init(file: "counter.a9285af9d50f9145.js", integrity: "sha256-qSha+dUP", bytes: 331)
    ])

    // MARK: - the manifest model

    @Test
    func `the manifest decodes the bun build output`() throws {
        let json = Array(
            #"{"counter":{"file":"counter.abc.js","integrity":"sha256-X=","bytes":331}}"#.utf8)
        let manifest = try AssetManifest(json: json)
        #expect(
            manifest.modules["counter"]
                == AssetManifest.Module(file: "counter.abc.js", integrity: "sha256-X=", bytes: 331))
    }

    // MARK: - the served-module script tags

    @Test
    func `a module component emits a content-hashed, SRI-pinned, nonced module script`() throws {
        let assets = AssetSink()
        _ = try ModuleWidget().renderHydratable(arena: CellArena(), assets: assets)  // populates the sink
        let tags = String(
            decoding: ADHTMLAssets.moduleScriptTags(
                for: assets, manifest: Self.manifest, nonce: "n0nc3", basePath: "/assets"),
            as: UTF8.self)
        #expect(
            tags == #"<script type="module" src="/assets/counter.a9285af9d50f9145.js" "#
                + #"integrity="sha256-qSha+dUP" nonce="n0nc3"></script>"#)
    }

    @Test
    func `a module absent from the manifest is skipped (graceful)`() throws {
        let assets = AssetSink()
        _ = try ModuleWidget().renderHydratable(arena: CellArena(), assets: assets)
        let tags = ADHTMLAssets.moduleScriptTags(
            for: assets, manifest: AssetManifest(modules: [:]), nonce: nil, basePath: "/assets")
        #expect(tags.isEmpty)
    }

    // MARK: - nonce stamping (the strict-CSP requirement)

    @Test
    func `the CSP nonce is stamped on the injected style and inline script`() throws {
        let html = String(
            decoding: try InlineWidget().renderHydratable(arena: CellArena(), nonce: "n0nc3"),
            as: UTF8.self)
        let hash = try Self.scopeHash(in: html)
        #expect(html.contains(#"<style nonce="n0nc3">[data-1="\#(hash)"] .a { color: blue }</style>"#))
        #expect(html.contains(#"<script nonce="n0nc3">console.log(1)</script>"#))
    }

    @Test
    func `with no nonce the core stays nonce-free (byte-identical to before)`() throws {
        let html = String(decoding: try InlineWidget().renderHydratable(arena: CellArena()), as: UTF8.self)
        #expect(html.contains("<style>"))  // no nonce attribute
        #expect(html.contains("<script>console.log(1)</script>"))
        #expect(!html.contains("nonce="))
    }

    // MARK: - the composed response (smoke)

    @Test
    func `adhtmlAssets composes a response without throwing`() throws {
        // The wrapper renders + appends the module tags; it returns an ADServe ResponseContent (opaque here
        // — the byte assertions above cover the logic; this proves the composition type-checks + runs).
        _ = try ResponseContent.adhtmlAssets(
            ModuleWidget(), manifest: Self.manifest, nonce: "n0nc3", assetPath: "/assets")
    }

    /// The `data-scope` value stamped on the first mount root.
    private static func scopeHash(in html: String) throws -> String {
        let start = try #require(html.firstRange(of: #"data-1=""#))
        let rest = html[start.upperBound...]
        let end = try #require(rest.firstRange(of: "\""))
        return String(rest[..<end.lowerBound])
    }
}
