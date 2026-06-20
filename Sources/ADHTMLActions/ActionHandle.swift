// The typed, refactor-safe reference to a server action (RFC-0020 Track 3 P3). `@Action` generates one as
// the peer `<func>Action`, and `.submits(to:)` consumes it — so a view names the action by SYMBOL
// (`PartActions.deletePartAction`), and renaming the handler is a compile error at the call site rather
// than a silent stringly-slug drift.

public import ADHTMLCore  // RegionID

/// A server action's call-site identity: its stable ``ActionID`` + the ``Region`` its response re-renders.
public struct ActionHandle: Sendable {
    public let id: ActionID
    public let region: RegionID

    public init(id: ActionID, region: RegionID) {
        self.id = id
        self.region = region
    }
}
