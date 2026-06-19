/// When the client runtime wires an island (ADR-0005, Astro's loading-contract directive). Emitted as
/// the island root's `data-adh-on` attribute; the runtime maps each case to a native browser API.
public enum LoadStrategy: Sendable, Equatable {
    /// Wire immediately on load.
    case load
    /// Wire when the main thread is idle (`requestIdleCallback`).
    case idle
    /// Wire when the island scrolls into view (`IntersectionObserver`).
    case visible
    /// Wire when a media query matches (`matchMedia`).
    case media(String)

    /// The `data-adh-on` attribute value.
    public var attributeValue: String {
        switch self {
            case .load: "load"
            case .idle: "idle"
            case .visible: "visible"
            case .media(let query): "media:\(query)"
        }
    }
}
