internal import SwiftDiagnostics
public import SwiftSyntax
internal import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// `@State var count = 0` — adds a peer `countSignal: Signal<Int>` accessor that resolves the property
/// to its reactive cell through the ambient `ADHTMLRenderContext` (ADR-0008). The stored property keeps
/// holding the initial value (the server-render default); `<name>Signal` is the `Signal` handle that
/// bindings (`.bind`) and behaviors (`.on(_, .increment(_))`) target. The enclosing type must be a
/// `Component` so each instance renders inside its own scope (distinct cells per instance).
///
/// It is a peer (not an accessor) macro on purpose: leaving `count` a plain stored `var` keeps the
/// memberwise initializer (`Counter(count: 7)`) working and avoids the storage/`init`-accessor dance —
/// the live value is the default the server evaluates once, and reactivity is the client's job.
public struct StateMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            varDecl.bindingSpecifier.tokenKind == .keyword(.var),
            varDecl.bindings.count == 1,
            let binding = varDecl.bindings.first,
            binding.accessorBlock == nil,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier
        else {
            context.diagnose(Diagnostic(node: node, message: ADHTMLDiagnostic.stateRequiresStoredVar))
            return []
        }

        let name = identifier.text
        guard let valueType = stateValueType(binding) else {
            context.diagnose(Diagnostic(node: binding, message: ADHTMLDiagnostic.stateNeedsType(name)))
            return []
        }

        // Mirror the original property's access level so external code can bind a `public` state cell.
        let access = accessModifier(varDecl)
        let accessor: DeclSyntax = """
            \(raw: access)var \(raw: name)Signal: Signal<\(raw: valueType)> {
                ADHTMLRenderContext.state(key: \(literal: name), default: \(raw: name))
            }
            """
        return [accessor]
    }
}

/// The Signal's value type: the explicit annotation if present, else inferred from a literal initializer
/// (`0`→Int, `0.0`→Double, `"x"`→String, `true`→Bool). `nil` when neither is available.
private func stateValueType(_ binding: PatternBindingSyntax) -> String? {
    if let annotation = binding.typeAnnotation?.type {
        return annotation.trimmedDescription
    }
    guard let initializer = binding.initializer?.value else { return nil }
    if initializer.is(IntegerLiteralExprSyntax.self) { return "Int" }
    if initializer.is(FloatLiteralExprSyntax.self) { return "Double" }
    if initializer.is(StringLiteralExprSyntax.self) { return "String" }
    if initializer.is(BooleanLiteralExprSyntax.self) { return "Bool" }
    return nil
}

/// The access-control keyword to mirror onto the generated accessor (`"public "`, `"package "`, …), or
/// `""` when the property uses the default access level.
private func accessModifier(_ decl: VariableDeclSyntax) -> String {
    let levels: Set<TokenKind> = [
        .keyword(.public), .keyword(.package), .keyword(.internal),
        .keyword(.fileprivate), .keyword(.private)
    ]
    guard let modifier = decl.modifiers.first(where: { levels.contains($0.name.tokenKind) }) else {
        return ""
    }
    return modifier.name.text + " "
}
