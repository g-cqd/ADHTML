# Upstream issue (filable) — swiftbuild links a `.macro` plugin into a downstream test bundle

> **Status:** ready to file against `swiftlang/swift-package-manager` (the `swiftbuild`/Swift Build
> integration). Tracked locally by [ADR-0008](../adr/0008-lean-macro-surface.md) and guarded by the
> `swiftbuild-macro-canary` CI job (which turns red when this is fixed). File it, then paste the issue
> URL into ADR-0008's build-system note and this header.

## Title

`swift build --build-tests` under the `swiftbuild` engine mislinks a `.macro` plugin into a test bundle (undefined SwiftSyntax symbols)

## Environment

- **Toolchain:** Swift 6.4 nightly (`swiftlang/swift:nightly-6.4-2026-06-18-jammy`) and the matching
  Xcode-beta toolchain on macOS 26.
- **Build system:** default `swiftbuild` engine. The classic `--build-system native` engine is **not**
  affected.
- **Tools version:** `swift-tools-version: 6.x` package.

## Summary

A package that declares a Swift macro (`.macro` target) and a library that **uses** that macro builds
and links cleanly under `swiftbuild` for libraries and executables. **Only test bundles fail**: building
tests under `swiftbuild` produces *undefined SwiftSyntax symbols* referenced from the macro plugin's
`…-testable.o`. `swiftbuild` is linking the `.macro` **plugin** target into the test executable as if it
were an ordinary link-time dependency (transitively, through the library the tests import), instead of
running it as a host compiler plugin at build time and linking nothing of it into the downstream binary.

## Minimal reproduction

A three-target package:

```
// Package.swift (6.x)
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "MacroMislink",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        // 1. the macro plugin (the sole place swift-syntax appears)
        .macro(
            name: "MyMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]),
        // 2. a library that USES the macro (declares + re-exports it)
        .target(name: "MyLib", dependencies: ["MyMacros"]),
        // 3. a test target that links the library
        .testTarget(name: "MyLibTests", dependencies: ["MyLib"]),
    ]
)
```

```swift
// Sources/MyMacros/Macro.swift — a trivial expression macro
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

public struct IdentityMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let arg = node.arguments.first?.expression else { return "()" }
        return "\(arg)"
    }
}

@main
struct Plugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [IdentityMacro.self]
}
```

```swift
// Sources/MyLib/MyLib.swift
@freestanding(expression) public macro identity<T>(_ value: T) -> T =
    #externalMacro(module: "MyMacros", type: "IdentityMacro")

public func wrapped(_ x: Int) -> Int { #identity(x) }
```

```swift
// Tests/MyLibTests/MyLibTests.swift
import Testing
@testable import MyLib

@Test func wraps() { #expect(wrapped(3) == 3) }
```

### Steps

```sh
swift build                                  # ✅ Build complete (libraries/executables)
swift build --build-system native --build-tests   # ✅ Build complete
swift build --build-system swiftbuild --build-tests   # ❌ undefined SwiftSyntax symbols
swift test --build-system swiftbuild               # ❌ same link failure (or SIGTRAP/SIGSEGV at run)
```

## Expected

`swift build --build-system swiftbuild --build-tests` links the test bundle cleanly. A `.macro` target is
a **host compiler plugin**: it is run during compilation of macro-annotated code and must never be linked
into a downstream test executable's image. (This is exactly what the `native` engine does.)

## Actual

The test bundle link fails with undefined `SwiftSyntax*` symbols pulled in from
`MyMacros-…-testable.o`, i.e. `swiftbuild` scoped the plugin target as a normal link-time dependency of
the test target rather than as a build-time compiler plugin. When the link does succeed in some shapes,
the resulting bundle crashes at runtime (SIGTRAP/SIGSEGV) because it was linked against the wrong
convention.

## Workaround

Build/test with the classic engine: `swift build/test --build-system native`. Libraries and executables
do **not** need it — only test targets that transitively link a library which uses the macro.

## Why it's a build-system bug, not a package-shape bug

The `.macro` declaration is already correct, and any test that compiles macro-annotated code must run the
plugin. There is no package restructure that avoids it — the defect is in how `swiftbuild` scopes the
plugin's link for test bundles, not in the package graph. The `native` engine builds the identical graph
correctly.
