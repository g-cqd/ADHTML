internal import SwiftDiagnostics

/// Diagnostics emitted by ADHTML's macros. Errors (not warnings): a malformed literal should fail the
/// build, which is the whole point of compile-time validation (ADR-0009).
enum ADHTMLDiagnostic: DiagnosticMessage {
    case attrRequiresStringLiteral
    case invalidAttributeName(String)

    var message: String {
        switch self {
            case .attrRequiresStringLiteral:
                "#attr requires a static string literal"
            case .invalidAttributeName(let name):
                #"'\#(name)' is not a valid HTML attribute name (no spaces, " ' > / = or control characters)"#
        }
    }

    var diagnosticID: MessageID {
        switch self {
            case .attrRequiresStringLiteral: MessageID(domain: "ADHTMLMacros", id: "attr.requiresStringLiteral")
            case .invalidAttributeName: MessageID(domain: "ADHTMLMacros", id: "attr.invalidName")
        }
    }

    var severity: DiagnosticSeverity { .error }
}
