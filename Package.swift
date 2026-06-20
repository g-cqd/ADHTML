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

// Compile-time type-check timing warnings (flag slow expressions / function bodies). These use unsafe
// flags, which would block version-based dependency resolution if placed on the library, so they live
// only on internal (non-exported) test + benchmark + fuzz targets.
let timingWarningFlags: [SwiftSetting] = [
    .unsafeFlags([
        "-Xfrontend", "-warn-long-function-bodies=100",
        "-Xfrontend", "-warn-long-expression-type-checking=100"
    ])
]
let benchSettings: [SwiftSetting] = strictSettings + timingWarningFlags
let testSettings: [SwiftSetting] =
    strictSettings + timingWarningFlags + [.unsafeFlags(["-enable-actor-data-race-checks"])]

// Dev / opt-in gates, mirroring ADJSON's `_DEV` / `_NIO` / `_FUZZ` model so consumers of the default
// products never resolve the heavier or host-coupling dependencies (ADR-0010).
let isDev = Context.environment["ADHTML_DEV"] != nil
let isNIO = Context.environment["ADHTML_NIO"] != nil
let isMarkdown = Context.environment["ADHTML_MARKDOWN"] != nil
let isObs = Context.environment["ADHTML_OBS"] != nil
let isSRI = Context.environment["ADHTML_SRI"] != nil
let isFuzz = Context.environment["ADHTML_FUZZ"] != nil

// AD* siblings resolve from a local checkout when `<DEP>_PATH` is set, else the published `main`.
func adPackage(env: String, url: String) -> Package.Dependency {
    if let path = Context.environment[env], !path.isEmpty { return .package(path: path) }
    return .package(url: url, branch: "main")
}
let adfoundationDependency = adPackage(env: "ADFOUNDATION_PATH", url: "https://github.com/g-cqd/ADFoundation.git")
let adjsonDependency = adPackage(env: "ADJSON_PATH", url: "https://github.com/g-cqd/ADJSON.git")
// The family's deterministic-testing toolkit (AsyncEventProbe, TestClock, gates, ConstrainedStack).
// Used by test targets only; consumers of the library products never resolve it.
let adtestkitDependency = adPackage(env: "ADTESTKIT_PATH", url: "https://github.com/g-cqd/ADTestKit.git")

// Default graph (all Foundation-free): ADFoundation (ADFCore byte/ASCII/hash primitives), ADJSON
// (ADJSONCore — the wire-state serializer's JSON emit + JSONMergePatch, RFC-0003/0007), swift-collections
// (OrderedCollections → deterministic attribute + wire key order), swift-syntax (macro target only).
var packageDependencies: [Package.Dependency] = [
    adfoundationDependency,
    adjsonDependency,
    adtestkitDependency,
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
if isNIO {
    // The ADServe response bridge (ADR-0012, RFC-0007 §3). ADServe already ships the transport
    // primitives (.html/.stream/.sse/Static/CSPNonce); ADHTMLNIO forwards ADHTML's AsyncHTMLByteSink to
    // ADServe's ResponseBodyWriter (both `[UInt8]`, shaped 1:1). Resolves from ADSERVE_PATH locally.
    packageDependencies.append(adPackage(env: "ADSERVE_PATH", url: "https://github.com/g-cqd/ADServe.git"))
}
if isMarkdown {
    packageDependencies.append(.package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"))
}
if isObs {
    packageDependencies.append(.package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"))
    packageDependencies.append(.package(url: "https://github.com/apple/swift-metrics.git", from: "2.4.0"))
    packageDependencies.append(.package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.1.0"))
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
            swiftSettings: strictSettings,
            plugins: buildPlugins),

        // Umbrella: re-exports the core, declares the macros (impl in ADHTMLMacros), adds document
        // assembly. Build with `--build-system native`: the newer `swiftbuild` engine on the current
        // Xcode-beta toolchain mislinks the `.macro` module into dependent test bundles (a SwiftPM/
        // toolchain issue, not ADHTML's). `native` handles macros correctly (ADR-0008; CONTRIBUTING).
        .target(
            name: "ADHTML",
            dependencies: ["ADHTMLCore", "ADHTMLMacros"],
            swiftSettings: strictSettings,
            plugins: buildPlugins),

        .testTarget(name: "ADHTMLCoreTests", dependencies: ["ADHTMLCore"], swiftSettings: testSettings),
        .testTarget(name: "ADHTMLTests", dependencies: ["ADHTML"], swiftSettings: testSettings),
        .testTarget(name: "ADHTMLXSSTests", dependencies: ["ADHTMLCore"], swiftSettings: testSettings),

        // The element/attribute table generator (ADR-0009). Run manually (`swift run ADHTMLCodegen`);
        // its output is committed under DOM/Generated. Not a product, so consumers never build it; it
        // depends only on Foundation (a dev-time tool, never shipped in a library product).
        .executableTarget(name: "ADHTMLCodegen", swiftSettings: strictSettings),

        // A lightweight, network-free release perf probe over ADHTMLCore (no swift-syntax / DEV deps).
        // Run: `swift run -c release ADHTMLPerfProbe`. Complements the ordo-one suite (the CI gate with
        // mallocCountTotal) for quick local before/after wall-clock measurement. Not a product.
        .executableTarget(name: "ADHTMLPerfProbe", dependencies: ["ADHTMLCore"], swiftSettings: strictSettings)
    ]
)

// --- Gated targets/products (each mirrors ADJSON's append-after-construction pattern) ---

if isNIO {
    // The ADServe response bridge: forward ADHTML's rendered bytes into ADServe's `ResponseContent`
    // (.html / .stream). Depends only on ADHTMLCore + ADServeCore (ADServe brings NIO transitively).
    package.products.append(.library(name: "ADHTMLNIO", targets: ["ADHTMLNIO"]))
    package.targets.append(
        .target(
            name: "ADHTMLNIO",
            dependencies: ["ADHTMLCore", .product(name: "ADServeCore", package: "ADServe")],
            swiftSettings: strictSettings))
    package.targets.append(
        .testTarget(
            name: "ADHTMLNIOTests",
            dependencies: ["ADHTMLNIO", .product(name: "ADTestKit", package: "ADTestKit")],
            swiftSettings: testSettings))
}
if isMarkdown {
    package.products.append(.library(name: "ADHTMLMarkdown", targets: ["ADHTMLMarkdown"]))
    package.targets.append(
        .target(
            name: "ADHTMLMarkdown",
            dependencies: ["ADHTMLCore", .product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: strictSettings))
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
if isObs {
    package.products.append(.library(name: "ADHTMLObservability", targets: ["ADHTMLObservability"]))
    package.targets.append(
        .target(
            name: "ADHTMLObservability",
            dependencies: [
                "ADHTMLCore",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "Tracing", package: "swift-distributed-tracing")
            ],
            swiftSettings: strictSettings))
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
