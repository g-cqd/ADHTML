// `@Component` expansion, pinned at the implementation (ComponentMacro): the plain conformance for
// a static component, the `isIsland` witness (+ access mirroring) when `@State`/`@Bound` members
// make it interactive, and the deliberate no-op when the conformance already exists. The macro
// emits NO diagnostics by design — every shape is valid; the negative case here is the no-op
// expansion. Behavioral coverage (auto-island render) lives in ADHTMLTests.

import SwiftSyntaxBuilder  // TypeSyntax's string-literal init (the `conformances:` list)
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@testable import ADHTMLMacros

/// The compiler passes the still-missing conformances via `conformingTo:`; model the normal case
/// (author did NOT write `: Component`) by declaring it on the spec.
private let componentSpecs: [String: MacroSpec] = [
    "Component": MacroSpec(type: ComponentMacro.self, conformances: ["Component"])
]
/// An empty `conformingTo:` list models the author having written `: Component` already.
private let alreadyConformingSpecs: [String: MacroSpec] = [
    "Component": MacroSpec(type: ComponentMacro.self)
]

private let staticSource: String = """
    @Component
    struct Badge {
        var body: String { "b" }
    }
    """
private let staticExpansion: String = """
    struct Badge {
        var body: String { "b" }
    }

    extension Badge: Component {
    }
    """

private let interactiveSource: String = """
    @Component
    struct Counter {
        @State var count = 0
    }
    """
private let interactiveExpansion: String = """
    struct Counter {
        @State var count = 0
    }

    extension Counter: Component {
        static var isIsland: Bool {
            true
        }
    }
    """

private let publicInteractiveSource: String = """
    @Component
    public struct Counter {
        @Bound var doubled: Reactive<Int> { $count.reactive * 2 }
    }
    """
private let publicInteractiveExpansion: String = """
    public struct Counter {
        @Bound var doubled: Reactive<Int> { $count.reactive * 2 }
    }

    extension Counter: Component {
        public static var isIsland: Bool {
            true
        }
    }
    """

private let redundantSource: String = """
    @Component
    struct Badge: Component {
        var body: String { "b" }
    }
    """
private let redundantExpansion: String = """
    struct Badge: Component {
        var body: String { "b" }
    }
    """

struct ComponentMacroExpansionTests {
    @Test func `a static component gains the plain Component conformance`() {
        expandsTo(staticSource, staticExpansion, macroSpecs: componentSpecs)
    }

    @Test func `a @State member flips the isIsland witness`() {
        expandsTo(interactiveSource, interactiveExpansion, macroSpecs: componentSpecs)
    }

    @Test func `a @Bound member also flips isIsland, and the witness mirrors the type's access`() {
        expandsTo(publicInteractiveSource, publicInteractiveExpansion, macroSpecs: componentSpecs)
    }

    @Test func `an existing Component conformance is a silent no-op (no duplicate extension)`() {
        expandsTo(redundantSource, redundantExpansion, macroSpecs: alreadyConformingSpecs)
    }
}
