// A presentational status / label pill — one of the small set of generic, app-agnostic components an
// author reaches for instead of hand-writing `<span class="pill …">` everywhere. Static (no island, no JS).

/// A compact status / label pill — `Pill("Active", tone: .positive)`. Renders `<span class="pill
/// pill-<tone>">label</span>`; the consumer's CSS supplies the palette, so ANY domain maps its own statuses
/// onto the generic tones (an inventory app's "Obsolete" → `.critical`, a CI app's "Passing" → `.positive`).
/// No domain coupling, no interactivity.
public struct Pill: Component {
    /// Generic semantic tones — an app maps its own status vocabulary onto these.
    public enum Tone: String, Sendable, CaseIterable {
        case neutral, positive, warning, critical, info
    }

    public let label: String
    public let tone: Tone

    public init(_ label: String, tone: Tone = .neutral) {
        self.label = label
        self.tone = tone
    }

    public var body: some HTML {
        span { label }.class("pill pill-\(tone.rawValue)")
    }
}
