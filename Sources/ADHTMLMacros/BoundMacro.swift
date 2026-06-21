internal import SwiftDiagnostics
public import SwiftSyntax
internal import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// `@Bound var inCart: Bool { $qty > 0 }` — a client-recomputable value derived from `@State` (RFC-0005
/// §3.5, ADR-0015). It adds a peer `inCartComputed: Computed<Bool>` that resolves the author's expression to
/// a REGISTERED computed cell through the ambient `ADHTMLRenderContext`. The cell serializes its formula as a
/// `WireExpr`, so the browser re-evaluates it reactively with no server round-trip (the proven
/// `Reactive`→`WireExpr`→`Computed` path). The handle (`<name>Computed`) is what `.bind(_:to:)`,
/// `.show(when:)`, `When(_:)`, … target.
///
/// It is a peer (not an accessor) macro: the original property stays — a plain computed property — and
/// `<name>Computed` is the registered handle. The derivation runs INSIDE the property getter (where `self`
/// and the ambient context exist), so referencing the component's `$state` projections is legal.
///
/// Two annotation forms:
///   • a VALUE type (`: Bool` / `: Int` / …) — the macro rewrites each `$state` reference in the getter into
///     its `.reactive` operand (`$qty` → `$qty.reactive`), so the formula is built from the closed operator
///     DSL while the original getter type-checks via the value-returning operators (`ReactiveReadable`);
///   • the explicit `: Reactive<T>` form — taken verbatim (the author already wrote the reactive operand).
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
        guard let computed = boundComputed(binding) else {
            context.diagnose(Diagnostic(node: binding, message: ADHTMLDiagnostic.boundNeedsReactiveType(name)))
            return []
        }
        guard let expression = boundReactiveExpression(binding) else {
            context.diagnose(Diagnostic(node: binding, message: ADHTMLDiagnostic.boundNeedsExpression(name)))
            return []
        }

        // The value-typed form maps each `$state` projection to its reactive operand so the SAME expression
        // builds the wire formula; the explicit `Reactive<T>` form is already in operand terms.
        let operand =
            computed.rewriteProjections
            ? ExprSyntax(ProjectionRewriter().rewrite(expression)) ?? expression
            : expression

        // Mirror the original property's access level so external code can reach a `public` computed handle.
        let access = accessModifier(varDecl)
        let accessor: DeclSyntax = """
            \(raw: access)var \(raw: name)Computed: \(raw: computed.type) {
                ADHTMLRenderContext.bound(\(operand.trimmed))
            }
            """
        return [accessor]
    }
}

/// Rewrites each `$state` projection reference (a `$`-prefixed identifier) into its `.reactive` operand, so a
/// value-typed `@Bound` body (`$qty > 0`) becomes the formula-building expression (`$qty.reactive > 0`).
private final class ProjectionRewriter: SyntaxRewriter {
    override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
        guard node.baseName.text.hasPrefix("$") else { return ExprSyntax(node) }
        // Build `$x.reactive` from the bare (trivia-stripped) reference, then re-attach the original
        // surrounding trivia so the operand's spacing in the enclosing expression is preserved (otherwise
        // `$qty > 0` would become `$qty.reactive> 0`, a parse error).
        let replacement: ExprSyntax = "\(node.trimmed).reactive"
        return
            replacement
            .with(\.leadingTrivia, node.leadingTrivia)
            .with(\.trailingTrivia, node.trailingTrivia)
    }
}

/// The peer's `Computed<…>` type + whether to rewrite `$state` projections. For `: Reactive<V>` the type is
/// `Computed<V>` (verbatim operand, no rewrite); for any other (value) annotation `T` the type is
/// `Computed<T>` and the getter's `$state` references are rewritten. `nil` when there is no annotation (the
/// value `V` is otherwise unknowable — a computed property's type cannot be inferred).
private func boundComputed(_ binding: PatternBindingSyntax) -> (type: String, rewriteProjections: Bool)? {
    guard let annotation = binding.typeAnnotation?.type else { return nil }
    if let identifierType = annotation.as(IdentifierTypeSyntax.self),
        identifierType.name.text == "Reactive",
        let generics = identifierType.genericArgumentClause
    {
        return ("Computed\(generics.trimmedDescription)", false)
    }
    return ("Computed<\(annotation.trimmedDescription)>", true)
}

/// The author's derived expression: the getter's single return expression (`{ expr }` / `{ return expr }` /
/// `get { … }`) — the form that can reference the component's `$state` projections. `nil` when absent.
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
