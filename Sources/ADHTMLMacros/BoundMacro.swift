internal import SwiftDiagnostics
public import SwiftSyntax
internal import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// `@Bound var inCart: Reactive<Bool> { qtySignal.reactive > 0 }` — a client-recomputable value derived
/// from `@State` (RFC-0005 §3.5, ADR-0015 Phase D). It adds a peer `inCartComputed: Computed<Bool>` that
/// resolves the author's `Reactive` expression to a REGISTERED computed cell through the ambient
/// `ADHTMLRenderContext`. The cell serializes its formula as a `WireExpr`, so the browser re-evaluates it
/// reactively with no server round-trip (the proven `Reactive`→`WireExpr`→`Computed` path). The handle
/// (`<name>Computed`) is what `.bind(_:to:)`, `.show(when:)`, `When(_:)`, … target.
///
/// It is a peer (not an accessor) macro, mirroring ``StateMacro``: the original property stays — a plain
/// computed property returning the raw `Reactive<T>` — and `<name>Computed` is the registered handle. The
/// derivation runs INSIDE the property getter (where `self` and the ambient context exist), so referencing
/// the component's `@State` signal peers is legal — the assignment-with-`=` form cannot, because Swift
/// forbids instance-member references in a stored-property initializer.
///
/// Phase 1 (here) is the EXPLICIT form: the author writes the `Reactive<T>` expression themselves (already
/// in the closed operator DSL), and the macro only wraps it in `ADHTMLRenderContext.bound(_:)`. The
/// body-parse form (`@Bound var total: Int { a + b }`, rewriting bare identifiers → signal refs) is a
/// deferred follow-up bounded by the same closed op set.
public struct BoundMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            varDecl.bindingSpecifier.tokenKind == .keyword(.var),
            varDecl.bindings.count == 1,
            let binding = varDecl.bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier
        else {
            context.diagnose(Diagnostic(node: node, message: ADHTMLDiagnostic.boundRequiresVar))
            return []
        }

        let name = identifier.text
        guard let computedType = boundComputedType(binding) else {
            context.diagnose(Diagnostic(node: binding, message: ADHTMLDiagnostic.boundNeedsReactiveType(name)))
            return []
        }
        guard let reactiveExpr = boundReactiveExpression(binding) else {
            context.diagnose(Diagnostic(node: binding, message: ADHTMLDiagnostic.boundNeedsExpression(name)))
            return []
        }

        // Mirror the original property's access level so external code can reach a `public` computed handle.
        let access = accessModifier(varDecl)
        let accessor: DeclSyntax = """
            \(raw: access)var \(raw: name)Computed: \(raw: computedType) {
                ADHTMLRenderContext.bound(\(reactiveExpr.trimmed))
            }
            """
        return [accessor]
    }
}

/// The peer's `Computed<V>` type, derived from the required `: Reactive<V>` annotation by swapping the base
/// name and reusing the generic clause verbatim (`Reactive<Bool>` → `Computed<Bool>`). `nil` when the
/// annotation is missing or is not a `Reactive<…>` — the only shape this phase accepts (the value `V` is
/// otherwise unknowable, since a computed property's type cannot be inferred).
private func boundComputedType(_ binding: PatternBindingSyntax) -> String? {
    guard let identifierType = binding.typeAnnotation?.type.as(IdentifierTypeSyntax.self),
        identifierType.name.text == "Reactive",
        let generics = identifierType.genericArgumentClause
    else {
        return nil
    }
    return "Computed\(generics.trimmedDescription)"
}

/// The author's `Reactive<T>` expression: the getter's single return expression (`{ expr }` / `{ return
/// expr }` / `get { … }`) — the form that can reference the component's `@State` signal peers — or, for an
/// instance-free reactive, the `= expr` initializer. `nil` when neither is present.
private func boundReactiveExpression(_ binding: PatternBindingSyntax) -> ExprSyntax? {
    if let initializer = binding.initializer?.value { return initializer }
    guard let accessors = binding.accessorBlock?.accessors else { return nil }
    switch accessors {
        case .getter(let body):
            return singleReturnedExpression(body)
        case .accessors(let list):
            guard let getter = list.first(where: { $0.accessorSpecifier.tokenKind == .keyword(.get) }),
                let body = getter.body?.statements
            else {
                return nil
            }
            return singleReturnedExpression(body)
    }
}

/// The lone expression of a single-statement getter body — either a bare expression (`{ expr }`) or an
/// explicit `return expr`. `nil` for a multi-statement body (not a simple derivation this phase handles).
private func singleReturnedExpression(_ body: CodeBlockItemListSyntax) -> ExprSyntax? {
    guard body.count == 1, let item = body.first?.item else { return nil }
    switch item {
        case .expr(let expr): return expr
        case .stmt(let stmt): return stmt.as(ReturnStmtSyntax.self)?.expression
        default: return nil
    }
}

/// The access-control keyword to mirror onto the generated handle (`"public "`, `"package "`, …), or `""`
/// for the default level — so a `public` component's `@Bound` handle is visible enough to bind externally.
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
