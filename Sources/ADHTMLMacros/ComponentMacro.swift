public import SwiftSyntax
internal import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

/// `@Component` — conforms a type to `Component`, the SwiftUI-style authoring marker for a composed
/// view (ADR-0008). Sugar for writing `: Component`; it pairs with `@State` so a reactive component
/// reads as `@Component struct Counter { @State var count = 0; var body: some HTML { … } }`.
///
/// The per-instance render scoping that makes `@State` cells distinct across instances lives in the
/// `Component` protocol's default `_render`, so this macro only needs to add the conformance — nothing
/// is synthesized into the body, keeping the expansion trivial and inspectable.
public struct ComponentMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // `protocols` is the subset of the declared `conformances:` the type does not already state.
        // Empty means the author already wrote `: Component`, so adding it again would be redundant.
        guard !protocols.isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): Component {}")]
    }
}
