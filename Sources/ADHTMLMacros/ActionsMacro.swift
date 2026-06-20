public import SwiftSyntax
internal import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// `@Actions` on a namespace `enum` — RFC-0020 Track 3 P3. A `MemberMacro` that walks the namespace's
/// `@Action`-annotated `static func`s and emits `static let all: [ServerAction]` (the boot registry), so an
/// app wires every action with one line (`ServerActionTable(PartActions.all).dispatchRoute(…)`) instead of a
/// second hand-maintained list. It re-reads each `@Action(slug, into:, page:)` attribute syntactically (the
/// `ComponentMacro` member-walk technique) — it does not depend on the `@Action` peer's expansion.
public struct ActionsMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        var entries: [String] = []
        for member in declaration.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self),
                let arguments = actionArguments(of: funcDecl),
                let slug = arguments.first(where: { $0.label == nil })?.expression.trimmedDescription
            else { continue }
            let returnPath =
                arguments.first(where: { $0.label?.text == "page" })?.expression.trimmedDescription ?? "nil"
            // The handler captures nothing (a static func reference) → @Sendable holds for the boot route.
            entries.append(
                "ServerAction(slug: \(slug), returnPath: \(returnPath)) { try Self.\(funcDecl.name.text)($0) }")
        }
        return ["static let all: [ServerAction] = [\(raw: entries.joined(separator: ", "))]"]
    }
}

/// The argument list of a member's `@Action(…)` attribute, or `nil` if it carries none.
private func actionArguments(of funcDecl: FunctionDeclSyntax) -> LabeledExprListSyntax? {
    for attribute in funcDecl.attributes {
        guard let attribute = attribute.as(AttributeSyntax.self),
            attribute.attributeName.trimmedDescription == "Action"
        else { continue }
        return attribute.arguments?.as(LabeledExprListSyntax.self)
    }
    return nil
}
