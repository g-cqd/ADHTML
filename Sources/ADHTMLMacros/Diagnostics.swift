internal import SwiftDiagnostics

/// Diagnostics emitted by ADHTML's macros. Errors (not warnings): a malformed literal should fail the
/// build, which is the whole point of compile-time validation (ADR-0009).
enum ADHTMLDiagnostic: DiagnosticMessage {
    case attrRequiresStringLiteral
    case invalidAttributeName(String)
    case boundRequiresVar
    case boundNeedsReactiveType(String)
    case boundNeedsExpression(String)

    var message: String {
        switch self {
            case .attrRequiresStringLiteral:
                "#attr requires a static string literal"
            case .invalidAttributeName(let name):
                #"'\#(name)' is not a valid HTML attribute name (no spaces, " ' > / = or control characters)"#
            case .boundRequiresVar:
                "@Bound must be applied to a single 'var' deriving a Reactive value"
            case .boundNeedsReactiveType(let name):
                "@Bound var \(name) needs an explicit type annotation "
                    + "(e.g. `@Bound var \(name): Bool { … }`) so its Computed type is known"
            case .boundNeedsExpression(let name):
                "@Bound var \(name) needs a Reactive expression — a getter `{ <expr> }` referencing the "
                    + "component's @State signals (the assignment `= <expr>` form cannot reference instance members)"
        }
    }

    var diagnosticID: MessageID {
        switch self {
            case .attrRequiresStringLiteral: MessageID(domain: "ADHTMLMacros", id: "attr.requiresStringLiteral")
            case .invalidAttributeName: MessageID(domain: "ADHTMLMacros", id: "attr.invalidName")
            case .boundRequiresVar: MessageID(domain: "ADHTMLMacros", id: "bound.requiresVar")
            case .boundNeedsReactiveType: MessageID(domain: "ADHTMLMacros", id: "bound.needsReactiveType")
            case .boundNeedsExpression: MessageID(domain: "ADHTMLMacros", id: "bound.needsExpression")
        }
    }

    var severity: DiagnosticSeverity { .error }
}
