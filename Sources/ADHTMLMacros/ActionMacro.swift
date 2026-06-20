public import SwiftSyntax
internal import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// `@Action("slug", into: region)` on a `static func` — RFC-0020 Track 3 P3. A `PeerMacro` (like `@State`)
/// that adds the typed call-site handle `<func>Action` next to the handler, so a view references the action
/// by symbol (`.submits(to: PartActions.deletePartAction)`) rather than by stringly slug — a rename of the
/// func is a compile error at the call site, not silent drift. The handle carries the action's id (the
/// slug's hash) + the ``Region`` (`into:`) its response re-renders.
public struct ActionMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else { return [] }
        let arguments = node.arguments?.as(LabeledExprListSyntax.self)
        guard let slugExpr = arguments?.first(where: { $0.label == nil })?.expression,
            let regionExpr = arguments?.first(where: { $0.label?.text == "into" })?.expression
        else { return [] }

        let funcName = funcDecl.name.text
        let handle: DeclSyntax = """
            static let \(raw: funcName)Action = ActionHandle(id: ActionID(slug: \(slugExpr)), region: \(regionExpr))
            """
        return [handle]
    }
}
