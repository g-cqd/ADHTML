// `@Action` / `@Actions` expansion, pinned at the implementation (RFC-0020 Track 3 P3): the typed
// `<func>Action` call-site handle, and the `static let all` boot registry synthesized from the
// namespace walk. Both macros are deliberately DIAGNOSTIC-FREE: a shape they don't recognize is a
// silent no-op (guard-return), pinned here as the negative cases. Behavioral coverage (dispatch +
// signing) lives in ADHTMLActionsTests (gated).

import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@testable import ADHTMLMacros

/// Separate specs per macro so each test isolates ONE expansion (an unexpanded `@Action` attribute
/// stays verbatim in the `@Actions` cases, proving the member walk is purely syntactic).
private let actionSpecs: [String: MacroSpec] = ["Action": MacroSpec(type: ActionMacro.self)]
private let actionsSpecs: [String: MacroSpec] = ["Actions": MacroSpec(type: ActionsMacro.self)]

private let handleSource: String = """
    enum PartActions {
        @Action("delete-part", into: partsRegion)
        static func deletePart(_ ctx: ActionContext) throws -> ActionOutcome {
            .ok
        }
    }
    """
private let handleExpansion: String = """
    enum PartActions {
        static func deletePart(_ ctx: ActionContext) throws -> ActionOutcome {
            .ok
        }

        static let deletePartAction = ActionHandle(id: ActionID(slug: "delete-part"), region: partsRegion)
    }
    """

private let missingRegionSource: String = """
    enum PartActions {
        @Action("delete-part")
        static func deletePart(_ ctx: ActionContext) throws -> ActionOutcome {
            .ok
        }
    }
    """
private let missingRegionExpansion: String = """
    enum PartActions {
        static func deletePart(_ ctx: ActionContext) throws -> ActionOutcome {
            .ok
        }
    }
    """

private let registrySource: String = """
    @Actions
    enum PartActions {
        @Action("delete-part", into: partsRegion)
        static func deletePart(_ ctx: ActionContext) throws -> ActionOutcome {
            .ok
        }
        @Action("rename-part", into: partsRegion, page: "/parts")
        static func renamePart(_ ctx: ActionContext) throws -> ActionOutcome {
            .ok
        }
    }
    """
private let registryExpansion: String = """
    enum PartActions {
        @Action("delete-part", into: partsRegion)
        static func deletePart(_ ctx: ActionContext) throws -> ActionOutcome {
            .ok
        }
        @Action("rename-part", into: partsRegion, page: "/parts")
        static func renamePart(_ ctx: ActionContext) throws -> ActionOutcome {
            .ok
        }

        static let all: [ServerAction] = [ServerAction(slug: "delete-part", returnPath: nil) {
                try Self.deletePart($0)
            }, ServerAction(slug: "rename-part", returnPath: "/parts") {
                try Self.renamePart($0)
            }]
    }
    """

private let emptyRegistrySource: String = """
    @Actions
    enum PartActions {
        static func helper() {
        }
    }
    """
private let emptyRegistryExpansion: String = """
    enum PartActions {
        static func helper() {
        }

        static let all: [ServerAction] = []
    }
    """

struct ActionMacrosExpansionTests {
    @Test func `@Action adds the typed call-site handle next to the handler`() {
        expandsTo(handleSource, handleExpansion, macroSpecs: actionSpecs)
    }

    @Test func `@Action without an into region is a silent no-op (deliberately diagnostic-free)`() {
        expandsTo(missingRegionSource, missingRegionExpansion, macroSpecs: actionSpecs)
    }

    @Test func `@Actions synthesizes the boot registry from the namespace's @Action members`() {
        expandsTo(registrySource, registryExpansion, macroSpecs: actionsSpecs)
    }

    @Test func `@Actions with no @Action members emits an empty registry (silent, diagnostic-free)`() {
        expandsTo(emptyRegistrySource, emptyRegistryExpansion, macroSpecs: actionsSpecs)
    }
}
