// swift-tools-version: 6.4
import CompilerPluginSupport
import PackageDescription

// Maximum concurrency safety + stricter checking, identical to the AD* family (e.g. ADJSON). These
// are dependency-safe (no unsafe flags), so the library is consumable via a version-pinned SwiftPM
// requirement. `.v6` turns on complete strict-concurrency; the upcoming features tighten existentials
// and import visibility.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

// ADHTMLCore additionally enables strict memory safety (SE-0458) + the compile-time-only `Lifetimes`
// feature (no runtime-floor impact; mirrors ADFoundation's kernel settings), so the engine's few unsafe
// ops are `unsafe`-annotated + lifetime-proven rather than convention-documented. Span/RawSpan back-deploy
// below the macOS-15 floor; UTF8Span / InlineArray (2025-SDK-gated) deliberately stay out.
let coreSettings: [SwiftSetting] =
    strictSettings + [.strictMemorySafety(), .enableExperimentalFeature("Lifetimes")]

// Compile-time type-check timing warnings (flag slow expressions / function bodies). These use unsafe
// flags, which would block version-based dependency resolution if placed on the library, so they live
// only on internal (non-exported) test + benchmark + fuzz targets.
// The budget is env-tunable because `treatAllWarnings(as: .error)` turns an overrun into a HARD build
// error while the measured quantity is type-check WALL TIME — structurally flaky on shared CI runners
// (observed 102–168 ms flips for bodies comfortably under 100 ms locally). CI exports
// AD_TYPECHECK_BUDGET_MS=250 to calibrate for runner noise; unset (local builds) it stays 100 so
// regressions still surface at developer-machine speed.
let typeCheckBudgetMS = Context.environment["AD_TYPECHECK_BUDGET_MS"].flatMap { Int($0) } ?? 100
let timingWarningFlags: [SwiftSetting] = [
    .unsafeFlags([
        "-Xfrontend", "-warn-long-function-bodies=\(typeCheckBudgetMS)",
        "-Xfrontend", "-warn-long-expression-type-checking=\(typeCheckBudgetMS)"
    ])
]
// The benchmark target gets a LOOSER type-check budget than the library/tests: the ordo-one plugin
// GENERATES a `registerBenchmarks()` boilerplate that aggregates every benchmark and grows with the
// suite, tripping the 100 ms gate as cases are added — a false positive on generated code, not a
// hand-written-quality signal. Tests keep the strict 100 ms budget.
let benchSettings: [SwiftSetting] =
    strictSettings + [.unsafeFlags(["-Xfrontend", "-warn-long-expression-type-checking=500"])]
let testSettings: [SwiftSetting] =
    strictSettings + timingWarningFlags + [.unsafeFlags(["-enable-actor-data-race-checks"])]

// Dev / opt-in gates, mirroring ADJSON's `_DEV` / `_FUZZ` model so consumers of the default
// products never resolve the heavier or host-coupling dependencies (ADR-0010).
let isDev = Context.environment["ADHTML_DEV"] != nil
// The ADServe response-bridge gate. Renamed ADHTML_NIO → ADHTML_SERVE (the target it gates imports
// no NIO — it is the ADServe response bridge; NIO only ever arrived transitively through ADServe,
// which is itself migrating off NIO). The old name stays accepted as a BACK-COMPAT ALIAS so
// existing scripts/CI invocations keep working; drop it once nothing sets ADHTML_NIO anymore.
let isServe = Context.environment["ADHTML_SERVE"] != nil || Context.environment["ADHTML_NIO"] != nil
let isMarkdown = Context.environment["ADHTML_MARKDOWN"] != nil
let isSRI = Context.environment["ADHTML_SRI"] != nil
let isFuzz = Context.environment["ADHTML_FUZZ"] != nil
// Tier-2 server-action closures (RFC-0020 Track 3): the signed `POST /_adh/act/<id>` dispatch + Region
// re-render + no-JS PRG. It builds on the serve bridge (`.adhtmlFragment`/`ctx.view`) and the ADServe
// routing + HMAC surface, so enabling it implies the ADServe graph (`needsServe`).
let isActions = Context.environment["ADHTML_ACTIONS"] != nil
// Tier-2 component-scoped assets (Track 4 / ADR-0021): the gated SERVING bridge — the `manifest.json` load,
// the `<script type=module src integrity nonce>` injection (nonce from `CSPNonceKey`), and the ADServe
// `Static("/assets")` wiring. The core asset surface (`ScopedStyle`/`Script`/`CSSScoper`/the injection) is
// unconditional in ADHTMLCore; only the serving bridge is gated. Builds on the serve bridge → `needsServe`.
let isAssets = Context.environment["ADHTML_ASSETS"] != nil
let needsServe = isServe || isActions || isAssets

// AD* siblings resolve from a local checkout when `<DEP>_PATH` is set, else the published `main`.
func adPackage(env: String, url: String) -> Package.Dependency {
    if let path = Context.environment[env], !path.isEmpty { return .package(path: path) }
    return .package(url: url, branch: "main")
}
let adfoundationDependency = adPackage(env: "ADFOUNDATION_PATH", url: "https://github.com/g-cqd/ADFoundation.git")
let adjsonDependency = adPackage(env: "ADJSON_PATH", url: "https://github.com/g-cqd/ADJSON.git")
// ADTestKit (the deterministic-testing toolkit) is folded into the ADFoundation umbrella package; the
// test targets reference it via `package: "ADFoundation"` (adfoundationDependency above).

// Default graph (all Foundation-free): ADFoundation (ADFCore byte/ASCII/hash primitives), ADJSON
// (ADJSONCore — the wire-state serializer's JSON emit + JSONMergePatch, RFC-0003/0007), swift-collections
// (OrderedCollections → deterministic attribute + wire key order), swift-syntax (macro target only).
var packageDependencies: [Package.Dependency] = [
    adfoundationDependency,
    adjsonDependency,
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0")
]
if isDev {
    if let path = Context.environment["ADBUILDTOOLS_PATH"], !path.isEmpty {
        packageDependencies.append(.package(path: path))
    } else {
        packageDependencies.append(.package(url: "https://github.com/g-cqd/ADBuildTools.git", branch: "main"))
    }
    packageDependencies.append(.package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"))
    packageDependencies.append(.package(url: "https://github.com/ordo-one/benchmark", from: "1.4.0"))
}
if needsServe {
    // The ADServe response bridge (ADR-0012, RFC-0007 §3). ADServe already ships the transport
    // primitives (.html/.stream/.sse/Static/CSPNonce); ADHTMLServe forwards ADHTML's AsyncHTMLByteSink
    // to ADServe's ResponseBodyWriter (both `[UInt8]`, shaped 1:1). Resolves from ADSERVE_PATH locally.
    // Also required by ADHTMLActions (Track 3) — hence `needsServe`. (NIO enters this graph only
    // transitively through ADServe, and ADServe's own de-NIO migration is in flight.)
    packageDependencies.append(adPackage(env: "ADSERVE_PATH", url: "https://github.com/g-cqd/ADServe.git"))
    // ADTestKit (AsyncEventProbe …) backs ADHTMLServeTests; it now lives in the default graph (above),
    // so the serve block no longer appends it.
}
if isMarkdown {
    packageDependencies.append(.package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"))
}
if isSRI {
    packageDependencies.append(.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"))
}

let orderedCollections: Target.Dependency = .product(name: "OrderedCollections", package: "swift-collections")
let adfCore: Target.Dependency = .product(name: "ADFCore", package: "ADFoundation")
let adjsonCore: Target.Dependency = .product(name: "ADJSONCore", package: "ADJSON")

// Build-time formatting enforcement attaches to the library only in dev/CI (gated like ADJSON).
let buildPlugins: [Target.PluginUsage] =
    isDev ? [.plugin(name: "LintBuild", package: "ADBuildTools")] : []

let package = Package(
    name: "ADHTML",
    // Floor pinned by stdlib `Synchronization.Mutex` (macOS 15 / iOS 18 / tvOS 18 / watchOS 11 /
    // visionOS 2). `Span`/`RawSpan` back-deploy further and are adopted; `UTF8Span`/`InlineArray`
    // (2025 SDK) are deliberately NOT adopted (they would raise the floor). Same rationale as ADJSON.
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        // The umbrella: core + macros + conveniences.
        .library(name: "ADHTML", targets: ["ADHTML"]),
        // The Foundation-free engine on its own (DOM, iterative renderer, escaping).
        .library(name: "ADHTMLCore", targets: ["ADHTMLCore"])
    ],
    dependencies: packageDependencies,
    targets: [
        // The only place swift-syntax appears. A valid, compiling plugin; macros land with the
        // reactivity subsystem (ADR-0008). Consumers resolve swift-syntax but it never enters runtime.
        .macro(
            name: "ADHTMLMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax")
            ],
            swiftSettings: strictSettings),

        // Foundation-free engine. Deps: OrderedCollections (deterministic attributes) + ADFCore
        // (ASCII/hash/byte primitives) — both Foundation-free with no transitive package deps.
        .target(
            name: "ADHTMLCore",
            dependencies: [orderedCollections, adfCore, adjsonCore],
            swiftSettings: coreSettings,
            plugins: buildPlugins),

        // Umbrella: re-exports the core, declares the macros (impl in ADHTMLMacros), adds document
        // assembly. Builds under the default `swiftbuild` engine: the macro/test-link bug that once
        // forced `--build-system native` (`swiftbuild` mislinking the `.macro` module into dependent
        // test bundles) is fixed on the pinned Swift 6.4 snapshot (ADR-0008; CONTRIBUTING).
        .target(
            name: "ADHTML",
            dependencies: ["ADHTMLCore", "ADHTMLMacros"],
            swiftSettings: strictSettings,
            plugins: buildPlugins),

        // The WHATWG reference tokenizer, used ONLY as a differential oracle by the parse tests and
        // the dev perf probe. A plain internal target — NOT a product and NOT in `.adbuildtools.json`
        // `shippedTargets` — so consumers of the shipped libraries never see its spec-shaped bulk,
        // and the shipped tree stays free of size-gate exceptions. Reads ADHTMLCore's token types +
        // the `package`-visible named-reference data table; its decode LOGIC stays independent.
        .target(name: "ADHTMLOracle", dependencies: ["ADHTMLCore"], swiftSettings: strictSettings),

        .testTarget(
            name: "ADHTMLCoreTests",
            dependencies: [
                "ADHTMLCore", "ADHTMLOracle", .product(name: "ADTestKit", package: "ADFoundation")
            ],
            swiftSettings: testSettings),
        .testTarget(name: "ADHTMLTests", dependencies: ["ADHTML"], swiftSettings: testSettings),

        // Expansion-assertion tests for the `.macro` target itself (the ADDB/URLBuilder idiom):
        // SwiftSyntaxMacrosGenericTestSupport's `assertMacroExpansion` with failures routed into
        // Swift Testing (the plain SwiftSyntaxMacrosTestSupport product is XCTest-bound). Behavioral
        // macro coverage (declaration -> plugin -> runtime) stays in ADHTMLTests; this target pins
        // the expansions + diagnostics of each macro implementation directly. `@testable import
        // ADHTMLMacros` links the macro OBJECT (its `@main` CompilerPlugin entry and every
        // SwiftSyntax reference) into the test bundle, so mirror the macro target's full
        // swift-syntax product set here or the symbols are undefined at link on a clean build.
        .testTarget(
            name: "ADHTMLMacrosTests",
            dependencies: [
                "ADHTMLMacros",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax")
            ],
            swiftSettings: testSettings),
        .testTarget(
            name: "ADHTMLXSSTests",
            dependencies: ["ADHTMLCore", .product(name: "ADTestKit", package: "ADFoundation")],
            swiftSettings: testSettings),

        // The element/attribute table generator (ADR-0009). Run manually (`swift run ADHTMLCodegen`);
        // its output is committed under DOM/Generated. Not a product, so consumers never build it; it
        // depends only on Foundation (a dev-time tool, never shipped in a library product).
        .executableTarget(name: "ADHTMLCodegen", swiftSettings: strictSettings),

        // The Swift-side generator for the shared wire-attribute vocabulary (RFC-0021 / ADR-0007). Reads
        // `wire-tokens.json` and regenerates BOTH `WireTokens.swift` (the renderer's constants) and
        // `ClientRuntime/src/tokens.js` (the runtime's constants) from one source — generation lives on
        // the Swift side, not in a JS script. A command plugin (not a build plugin) so it never runs
        // during a normal `swift build`: invoke `swift package --allow-writing-to-package-directory
        // generate-wire-tokens`. The committed outputs are guarded by parity tests on both sides.
        .plugin(
            name: "GenerateWireTokens",
            capability: .command(
                intent: .custom(
                    verb: "generate-wire-tokens",
                    description: "Regenerate the shared wire-token constants (Swift + JS) from wire-tokens.json"),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "Regenerate WireTokens.swift and ClientRuntime/src/tokens.js from wire-tokens.json")
                ])),

        // A lightweight, network-free release perf probe over ADHTMLCore (no swift-syntax / DEV deps).
        // Run: `swift run -c release ADHTMLPerfProbe`. Complements the ordo-one suite (the CI gate with
        // mallocCountTotal) for quick local before/after wall-clock measurement. Not a product.
        // ADHTMLOracle backs its correctness cross-check (tape vs reference tokenizer).
        .executableTarget(
            name: "ADHTMLPerfProbe",
            dependencies: ["ADHTMLCore", "ADHTMLOracle"],
            swiftSettings: strictSettings),

        // A multi-file example app (RFC-0005 §7): components across files, implicit islands (@State ->
        // auto-island), a slotted layout, typed attribute enums + events. Built (not a product) so the
        // authoring DSL stays compilable; `swift run Storefront` prints the catalog page. Uses the
        // umbrella (macros); builds under the default engine (no `--build-system native` — ADR-0008).
        .executableTarget(
            name: "Storefront", dependencies: ["ADHTML"], path: "Examples/Storefront",
            swiftSettings: strictSettings)
    ]
)

// --- Gated targets/products (each mirrors ADJSON's append-after-construction pattern) ---

if needsServe {
    // The ADServe response bridge: forward ADHTML's rendered bytes into ADServe's `ResponseContent`
    // (.html / .stream). Depends only on ADHTMLCore + ADServeCore — it imports no NIO itself (NIO is
    // transitive via ADServe while ADServe's de-NIO migration completes; the target's former name,
    // ADHTMLNIO, was a misnomer). Built whenever the ADServe graph is needed (explicit ADHTML_SERVE
    // — or the ADHTML_NIO back-compat alias — or ADHTMLActions/ADHTMLAssets depend on it).
    package.products.append(.library(name: "ADHTMLServe", targets: ["ADHTMLServe"]))
    package.targets.append(
        .target(
            name: "ADHTMLServe",
            dependencies: [
                "ADHTMLCore",
                .product(name: "ADServeCore", package: "ADServe"),
                // ADServeDSL for the `HandlerContext` seam — the dual-mode `ctx.view(page:fragment:)`
                // reads `ctx.isFragment` (RFC-0019 C1) to pick page vs fragment (RFC-0020 §1).
                .product(name: "ADServeDSL", package: "ADServe")
            ],
            swiftSettings: strictSettings))
    package.targets.append(
        .testTarget(
            name: "ADHTMLServeTests",
            dependencies: ["ADHTMLServe", .product(name: "ADTestKit", package: "ADFoundation")],
            swiftSettings: testSettings))
}
if isActions {
    // Tier-2 server-action closures (RFC-0020 Track 3): the signed `POST /_adh/act/<id>` dispatch + Region
    // re-render + no-JS PRG. Builds on the serve bridge (`.adhtmlFragment`/`ctx.view`) + the ADServe routing
    // (`POST`/`RouteNode`) + the shared `ADServeCore.HMACSigner`. The `@Endpoint`/`@Endpoints` macros (P3)
    // are declared here, with impls in the ADHTMLMacros plugin.
    package.products.append(.library(name: "ADHTMLActions", targets: ["ADHTMLActions"]))
    package.targets.append(
        .target(
            name: "ADHTMLActions",
            dependencies: [
                "ADHTMLCore", "ADHTMLServe", "ADHTMLMacros", adfCore,
                .product(name: "ADServeCore", package: "ADServe"),
                .product(name: "ADServeDSL", package: "ADServe")
            ],
            swiftSettings: strictSettings))
    package.targets.append(
        .testTarget(
            name: "ADHTMLActionsTests",
            dependencies: ["ADHTMLActions", .product(name: "ADTestKit", package: "ADFoundation")],
            swiftSettings: testSettings))
}
if isAssets {
    // Track 4 component-scoped assets — the gated SERVING bridge (ADR-0021). Loads the bun-produced
    // `manifest.json`, injects `<script type=module src integrity nonce>` for a page's `.module`
    // components, and pairs with ADServe `Static("/assets")`. SRI is computed at BUILD time by bun
    // (parity-pinned to `ADHTMLSRI` by the ClientRuntime test), so the bridge trusts the manifest's
    // integrity — no swift-crypto runtime dep here. Builds on the serve bridge for `ResponseContent` +
    // `CSPNonceKey`.
    package.products.append(.library(name: "ADHTMLAssets", targets: ["ADHTMLAssets"]))
    package.targets.append(
        .target(
            name: "ADHTMLAssets",
            dependencies: [
                "ADHTMLCore", "ADHTMLServe",
                .product(name: "ADServeCore", package: "ADServe")
            ],
            swiftSettings: strictSettings))
    package.targets.append(
        .testTarget(
            name: "ADHTMLAssetsTests",
            dependencies: ["ADHTMLAssets"],
            swiftSettings: testSettings))
}
if isMarkdown {
    package.products.append(.library(name: "ADHTMLMarkdown", targets: ["ADHTMLMarkdown"]))
    package.targets.append(
        .target(
            name: "ADHTMLMarkdown",
            dependencies: ["ADHTMLCore", .product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: strictSettings))
    package.targets.append(
        .testTarget(
            name: "ADHTMLMarkdownTests", dependencies: ["ADHTMLMarkdown", "ADHTMLCore"],
            swiftSettings: testSettings))
}
if isSRI {
    // swift-crypto SHA-256 — for Subresource Integrity of the client runtime only (ADR-0011).
    package.products.append(.library(name: "ADHTMLSRI", targets: ["ADHTMLSRI"]))
    package.targets.append(
        .target(
            name: "ADHTMLSRI",
            dependencies: ["ADHTMLCore", adfCore, .product(name: "Crypto", package: "swift-crypto")],
            swiftSettings: strictSettings))
    package.targets.append(
        .testTarget(name: "ADHTMLSRITests", dependencies: ["ADHTMLSRI"], swiftSettings: testSettings))
}
if isFuzz {
    // `-parse-as-library` (libFuzzer supplies `main`) + `-sanitize=fuzzer`. Linux-only capability of
    // the toolchain (the Darwin SDK rejects the flag), so this builds/runs in the Linux CI fuzz job.
    package.targets.append(
        .executableTarget(
            name: "ADHTMLFuzz",
            dependencies: ["ADHTMLCore"],
            swiftSettings: strictSettings + [.unsafeFlags(["-parse-as-library", "-sanitize=fuzzer"])],
            linkerSettings: [.unsafeFlags(["-sanitize=fuzzer"])]))
    package.products.append(.executable(name: "ADHTMLFuzz", targets: ["ADHTMLFuzz"]))
}
if isDev {
    // ordo-one/benchmark suite (ADHTML_DEV-gated): `swift package benchmark` with p-percentile gates.
    package.targets.append(
        .executableTarget(
            name: "ADHTMLSuite",
            dependencies: ["ADHTML", .product(name: "Benchmark", package: "benchmark")],
            path: "Benchmarks/ADHTMLSuite",
            swiftSettings: benchSettings,
            plugins: [.plugin(name: "BenchmarkPlugin", package: "benchmark")]))
}
