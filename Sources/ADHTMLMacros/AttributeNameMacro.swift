internal import SwiftDiagnostics
public import SwiftSyntax
internal import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// `#attr("name")` — validates `name` is a valid HTML attribute token at compile time (ADR-0008/0009),
/// then expands to the literal. A malformed name is a compile-time diagnostic, so an invalid attribute
/// name fails the build instead of slipping into rendered HTML.
public struct AttributeNameMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let argument = node.arguments.first?.expression,
            let literal = argument.as(StringLiteralExprSyntax.self),
            let value = literal.singleStringSegment
        else {
            context.diagnose(Diagnostic(node: node, message: ADHTMLDiagnostic.attrRequiresStringLiteral))
            return "\"\""
        }
        if !isValidAttributeName(value) {
            context.diagnose(Diagnostic(node: literal, message: ADHTMLDiagnostic.invalidAttributeName(value)))
        }
        return ExprSyntax(literal)
    }
}

extension StringLiteralExprSyntax {
    /// The content when this literal is a single static string segment (no interpolation), else `nil`.
    var singleStringSegment: String? {
        guard segments.count == 1, case .stringSegment(let segment) = segments.first else { return nil }
        return segment.content.text
    }
}

extension AttributeNameMacro {
    /// A valid HTML attribute name: non-empty, no control characters, and none of space `"` `'` `>` `/`
    /// `=` (the HTML attribute-name grammar).
    private static func isValidAttributeName(_ name: String) -> Bool {
        if name.isEmpty { return false }
        for scalar in name.unicodeScalars {
            if scalar.value <= 0x1F || scalar.value == 0x7F { return false }
            switch scalar {
                case " ", "\"", "'", ">", "/", "=": return false
                default: continue
            }
        }
        return true
    }
}
