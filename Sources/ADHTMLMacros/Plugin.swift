// The compiler-plugin entry for ADHTML's macros (ADR-0008). swift-syntax is isolated to this `.macro`
// target. The `swiftbuild` macro/test-link bug that once forced `--build-system native` (the engine
// mislinking a `.macro` module into dependent test bundles) is fixed on the pinned Swift 6.4 snapshot,
// so the package builds/tests on the default engine. See CONTRIBUTING / the umbrella target comment.
internal import SwiftCompilerPlugin
internal import SwiftSyntaxMacros

@main
struct ADHTMLMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        AttributeNameMacro.self, BoundMacro.self, ComponentMacro.self,
        ActionMacro.self, ActionsMacro.self
    ]
}
