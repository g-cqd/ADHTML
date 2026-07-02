// `#attr` expansion + diagnostics, pinned at the implementation (AttributeNameMacro). The behavioral
// end (`#attr("data-foo") == "data-foo"` through the plugin) lives in ADHTMLTests/MacroTests.

import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@testable import ADHTMLMacros

private let attrSpecs: [String: MacroSpec] = ["attr": MacroSpec(type: AttributeNameMacro.self)]

private let invalidNameMessage: String =
    #"'bad name' is not a valid HTML attribute name (no spaces, " ' > / = or control characters)"#

struct AttributeNameMacroExpansionTests {
    @Test func `a valid attribute name expands to its literal`() {
        expandsTo(
            #"let name = #attr("data-part-id")"#,
            #"let name = "data-part-id""#,
            macroSpecs: attrSpecs)
    }

    @Test func `an invalid name is a compile-time error and still expands to the literal`() {
        // The macro diagnoses AND returns the literal (not a placeholder), so downstream type
        // checking stays quiet while the build fails on the diagnostic alone.
        expandsTo(
            #"let name = #attr("bad name")"#,
            #"let name = "bad name""#,
            diagnostics: [DiagnosticSpec(message: invalidNameMessage, line: 1, column: 18)],
            macroSpecs: attrSpecs)
    }

    @Test func `a non-literal argument is rejected and expands to the empty literal`() {
        expandsTo(
            "let name = #attr(dynamic)",
            #"let name = """#,
            diagnostics: [
                DiagnosticSpec(message: "#attr requires a static string literal", line: 1, column: 12)
            ],
            macroSpecs: attrSpecs)
    }

    @Test func `an interpolated literal is rejected (not statically validatable)`() {
        expandsTo(
            #"let name = #attr("data-\(kind)")"#,
            #"let name = """#,
            diagnostics: [
                DiagnosticSpec(message: "#attr requires a static string literal", line: 1, column: 12)
            ],
            macroSpecs: attrSpecs)
    }
}
