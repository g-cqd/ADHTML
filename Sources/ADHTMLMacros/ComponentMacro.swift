public import SwiftSyntax
internal import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// `@Component` — conforms a type to `Component` (SwiftUI-style marker for a composed view, ADR-0008). A
/// component with `@State`/`@Bound` additionally gets `static var isIsland { true }`, so it AUTO-WRAPS
/// its body in a hydration island with an inferred scope — the author writes no `Island`/`scope`/`.id`
/// (RFC-0005 §3.0). A static one stays a plain `Component` and renders inline (no island, no JS).
/// Per-instance render scoping + the island wrap live in the `Component` default `_render`.
public struct ComponentMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // `protocols` is empty when the author already wrote `: Component`, so adding it again is redundant.
        guard !protocols.isEmpty else { return [] }
        guard hasReactiveState(declaration) else {
            return [try ExtensionDeclSyntax("extension \(type.trimmed): Component {}")]
        }
        // Interactive: flip `isIsland` so the component auto-wraps as an island. Mirror the type's access
        // so the witness is visible enough for a `public` component's conformance.
        let access = accessModifier(declaration)
        return [
            try ExtensionDeclSyntax(
                """
                extension \(type.trimmed): Component {
                    \(raw: access)static var isIsland: Bool { true }
                }
                """)
        ]
    }
}

/// Whether the type has any `@State` / `@Bound` member — i.e. it is interactive (renders as an island).
private func hasReactiveState(_ declaration: some DeclGroupSyntax) -> Bool {
    for member in declaration.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
        for attribute in varDecl.attributes {
            let name =
                attribute.as(AttributeSyntax.self)?.attributeName
                .as(IdentifierTypeSyntax.self)?
                .name.text
            if name == "State" || name == "Bound" { return true }
        }
    }
    return false
}

/// The access-control keyword to mirror onto the generated `isIsland` (`"public "`, `"package "`, …), or
/// `""` for the default level — so a `public` component's island witness is public enough.
private func accessModifier(_ declaration: some DeclGroupSyntax) -> String {
    let levels: Set<TokenKind> = [
        .keyword(.public), .keyword(.package), .keyword(.internal),
        .keyword(.fileprivate), .keyword(.private)
    ]
    guard let modifier = declaration.modifiers.first(where: { levels.contains($0.name.tokenKind) }) else {
        return ""
    }
    return modifier.name.text + " "
}
