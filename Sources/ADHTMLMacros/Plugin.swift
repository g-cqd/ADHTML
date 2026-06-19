// The compiler-plugin entry for ADHTML's macros (ADR-0008). It is a valid, compiling plugin now; the
// macro set (`@Component`, `#html`, `#attr`, island registration) lands with the reactivity subsystem
// (RFC-0003). Keeping the target present locks the swift-syntax gating and the build graph.
internal import SwiftCompilerPlugin
internal import SwiftSyntaxMacros

@main
struct ADHTMLMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = []
}
