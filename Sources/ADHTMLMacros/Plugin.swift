// The compiler-plugin entry for ADHTML's macros (ADR-0008). The macro set (`#attr`, `@Component`,
// `@State`, `#html`) is designed but NOT yet wired: on the current Xcode-beta toolchain, a test target
// that transitively depends on a `.macro` target fails to link (the macro module is pulled into the
// test bundle — a SwiftPM/toolchain issue, not an ADHTML one). The target stays a valid, compiling
// placeholder so the gating + graph are locked; macros activate once that issue is resolved.
internal import SwiftCompilerPlugin
internal import SwiftSyntaxMacros

@main
struct ADHTMLMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = []
}
