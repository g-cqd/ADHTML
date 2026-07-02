// The shared expansion-assertion helper for the ADHTMLMacros suite — the family's macro-test idiom
// (ADDB / URLBuilder): swift-syntax's SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion with
// failures routed into Swift Testing via Issue.record. (The SwiftSyntaxMacrosTestSupport product is
// XCTest-bound; the *Generic* support is the one usable under @Test/#expect.)

import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// Asserts `source` expands to exactly `expanded` with exactly `diagnostics`, under `macroSpecs`.
func expandsTo(
    _ source: String,
    _ expanded: String,
    diagnostics: [DiagnosticSpec] = [],
    macroSpecs: [String: MacroSpec]
) {
    assertMacroExpansion(
        source,
        expandedSource: expanded,
        diagnostics: diagnostics,
        macroSpecs: macroSpecs,
        failureHandler: { spec in
            Issue.record(
                Comment(rawValue: spec.message),
                sourceLocation: Testing.SourceLocation(
                    fileID: spec.location.fileID,
                    filePath: spec.location.filePath,
                    line: spec.location.line,
                    column: spec.location.column
                )
            )
        }
    )
}
