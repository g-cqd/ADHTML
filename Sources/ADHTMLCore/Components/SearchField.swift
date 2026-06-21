// A live search input — one of the generic, app-agnostic components. It hides the form + input + RFC-0019
// action wiring behind one call; with the runtime off it degrades to a plain GET form (the server filters
// and re-renders). No domain knowledge — the caller supplies only the request path + the region to morph.

/// A search input that live-updates a region — `SearchField(name: "q", submitsTo: "/parts", morphing:
/// "results")`. Typing debounces a GET to `submitsTo` (carrying the field) and morphs `#morphing` in place;
/// no JS → a normal GET form. The author never writes the `data-adh-*` action attributes by hand.
public struct SearchField: Component {
    public let name: String
    public let submitsTo: String
    public let morphing: String
    public let placeholder: String
    public let debounce: Duration

    /// `name` is the query field (and GET parameter); `submitsTo` is the request path whose response
    /// fragment replaces the `morphing` region in place; `debounce` coalesces keystrokes (default 150 ms).
    public init(
        name: String, submitsTo: String, morphing: String,
        placeholder: String = "Search…", debounce: Duration = .milliseconds(150)
    ) {
        self.name = name
        self.submitsTo = submitsTo
        self.morphing = morphing
        self.placeholder = placeholder
        self.debounce = debounce
    }

    public var body: some HTML {
        form {
            input()
                .type("search").name(name).placeholder(placeholder)
                .attribute("autocomplete", "off")
                .action(.get(submitsTo).trigger(.input).debounce(debounce).target(IslandID(morphing)))
        }
        .attribute("method", "get").attribute("action", submitsTo).class("searchfield")
    }
}
