// The compiler-plugin entry for ADHTML's macros (ADR-0008). swift-syntax is isolated to this `.macro`
// target. NOTE: the package builds with `--build-system native` (the classic build system); the newer
// `swiftbuild` engine on the current Xcode-beta toolchain mislinks a `.macro` module into dependent
// test bundles. See CONTRIBUTING / the umbrella target comment.
internal import SwiftCompilerPlugin
internal import SwiftSyntaxMacros

@main
struct ADHTMLMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        AttributeNameMacro.self, StateMacro.self, BoundMacro.self, ComponentMacro.self,
        ActionMacro.self, ActionsMacro.self
    ]
}
