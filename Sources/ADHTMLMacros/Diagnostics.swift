internal import SwiftDiagnostics

/// Diagnostics emitted by ADHTML's macros. Errors (not warnings): a malformed literal should fail the
/// build, which is the whole point of compile-time validation (ADR-0009).
enum ADHTMLDiagnostic: DiagnosticMessage {
    case attrRequiresStringLiteral
    case invalidAttributeName(String)
    case stateRequiresStoredVar
    case stateNeedsType(String)

    var message: String {
        switch self {
            case .attrRequiresStringLiteral:
                "#attr requires a static string literal"
            case .invalidAttributeName(let name):
                #"'\#(name)' is not a valid HTML attribute name (no spaces, " ' > / = or control characters)"#
            case .stateRequiresStoredVar:
                "@State must be applied to a single stored 'var' (not 'let' or a computed property)"
            case .stateNeedsType(let name):
                "@State var \(name) needs an explicit type or a literal initializer "
                    + "(e.g. `@State var \(name): Int = 0`) so its Signal type is known"
        }
    }

    var diagnosticID: MessageID {
        switch self {
            case .attrRequiresStringLiteral: MessageID(domain: "ADHTMLMacros", id: "attr.requiresStringLiteral")
            case .invalidAttributeName: MessageID(domain: "ADHTMLMacros", id: "attr.invalidName")
            case .stateRequiresStoredVar: MessageID(domain: "ADHTMLMacros", id: "state.requiresStoredVar")
            case .stateNeedsType: MessageID(domain: "ADHTMLMacros", id: "state.needsType")
        }
    }

    var severity: DiagnosticSeverity { .error }
}
