// `@Bound` expansion + diagnostics, pinned at the implementation (BoundMacro): the peer
// `<name>Computed` handle, the `$state` -> `$state.reactive` rewrite for value-typed annotations,
// the verbatim `Reactive<T>` form, access mirroring, and each error path. Behavioral coverage
// (register + wire round-trip) lives in ADHTMLTests/BoundMacroTests.

import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@testable import ADHTMLMacros

private let boundSpecs: [String: MacroSpec] = ["Bound": MacroSpec(type: BoundMacro.self)]

// Expected expansions hoisted to file scope (typed) — keeps each @Test body inside the family's
// 100 ms type-check budget.
private let valueTypedSource: String = """
    struct Cart {
        @Bound var inCart: Bool { $qty > 0 }
    }
    """
private let valueTypedExpansion: String = """
    struct Cart {
        var inCart: Bool { $qty > 0 }

        var inCartComputed: Computed<Bool> {
            ADHTMLRenderContext.bound($qty.reactive > 0)
        }
    }
    """

private let reactiveTypedSource: String = """
    struct Stat {
        @Bound var doubled: Reactive<Int> { $count.reactive * 2 }
    }
    """
private let reactiveTypedExpansion: String = """
    struct Stat {
        var doubled: Reactive<Int> { $count.reactive * 2 }

        var doubledComputed: Computed<Int> {
            ADHTMLRenderContext.bound($count.reactive * 2)
        }
    }
    """

private let publicSource: String = """
    public struct Cart {
        @Bound public var inCart: Bool { $qty > 0 }
    }
    """
private let publicExpansion: String = """
    public struct Cart {
        public var inCart: Bool { $qty > 0 }

        public var inCartComputed: Computed<Bool> {
            ADHTMLRenderContext.bound($qty.reactive > 0)
        }
    }
    """

private let boundOnLetSource: String = """
    struct Cart {
        @Bound let inCart: Bool
    }
    """
private let boundOnLetExpansion: String = """
    struct Cart {
        let inCart: Bool
    }
    """

private let missingTypeSource: String = """
    struct Cart {
        @Bound var inCart = false
    }
    """
private let missingTypeExpansion: String = """
    struct Cart {
        var inCart = false
    }
    """

private let missingBodySource: String = """
    struct Cart {
        @Bound var inCart: Bool
    }
    """
private let missingBodyExpansion: String = """
    struct Cart {
        var inCart: Bool
    }
    """

private let missingTypeMessage: String =
    "@Bound var inCart needs an explicit type annotation "
    + "(e.g. `@Bound var inCart: Bool { … }`) so its Computed type is known"
private let missingBodyMessage: String =
    "@Bound var inCart needs a Reactive expression — a getter `{ <expr> }` referencing the "
    + "component's @State signals (the assignment `= <expr>` form cannot reference instance members)"

struct BoundMacroExpansionTests {
    @Test func `a value-typed derivation adds the Computed peer with $state rewritten to .reactive`() {
        expandsTo(valueTypedSource, valueTypedExpansion, macroSpecs: boundSpecs)
    }

    @Test func `an explicit Reactive annotation is taken verbatim (no projection rewrite)`() {
        expandsTo(reactiveTypedSource, reactiveTypedExpansion, macroSpecs: boundSpecs)
    }

    @Test func `the peer mirrors the property's access level`() {
        expandsTo(publicSource, publicExpansion, macroSpecs: boundSpecs)
    }

    @Test func `@Bound on a let is rejected`() {
        expandsTo(
            boundOnLetSource, boundOnLetExpansion,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Bound must be applied to a single 'var' deriving a Reactive value",
                    line: 2, column: 5)
            ],
            macroSpecs: boundSpecs)
    }

    @Test func `a missing type annotation is rejected (the Computed type would be unknowable)`() {
        expandsTo(
            missingTypeSource, missingTypeExpansion,
            diagnostics: [DiagnosticSpec(message: missingTypeMessage, line: 2, column: 16)],
            macroSpecs: boundSpecs)
    }

    @Test func `a missing derivation body is rejected`() {
        expandsTo(
            missingBodySource, missingBodyExpansion,
            diagnostics: [DiagnosticSpec(message: missingBodyMessage, line: 2, column: 16)],
            macroSpecs: boundSpecs)
    }
}
