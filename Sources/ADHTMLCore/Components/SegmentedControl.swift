// A segmented control / tab strip bound to a signal — one of the generic, app-agnostic components. It hides
// the button + behavior + active-state wiring: the author owns ONE `Signal` and writes the options; clicking
// a segment sets the signal client-side and the active segment styles itself. No domain knowledge.

/// A segmented control bound to a `Signal<String>` — `SegmentedControl(selection: $density, segments:
/// [.init("comfortable", "Comfortable"), .init("compact", "Compact")])`. Clicking a segment sets the bound
/// signal (so other views can react to it — e.g. a grid's density class); the matching segment gets `.on`.
/// The author writes no buttons, no `.set` behaviors, no active-state `classToggle`.
public struct SegmentedControl: Component {
    public struct Segment: Sendable {
        public let value: String
        public let label: String
        public init(_ value: String, _ label: String) {
            self.value = value
            self.label = label
        }
    }

    public let selection: Signal<String>
    public let segments: [Segment]
    public let ariaLabel: String

    public init(selection: Signal<String>, segments: [Segment], ariaLabel: String = "Options") {
        self.selection = selection
        self.segments = segments
        self.ariaLabel = ariaLabel
    }

    public var body: some HTML {
        div {
            _HTMLArray(
                segments.map { segment in
                    button { segment.label }
                        .type("button").class("seg-btn")
                        .classToggle("on", when: selection.reactive == segment.value)
                        .on(.click, .set(selection, to: segment.value))
                })
        }
        .class("seg").attribute("role", "tablist").attribute("aria-label", ariaLabel)
    }
}
