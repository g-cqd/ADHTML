// The `TokenField` combobox (RFC-0020 §5 = RFC-0021 P9) — the refined-architecture proof. It is composed
// ENTIRELY from the closed declarative primitives, no hand-written JS: P1 `.model` (the query is state),
// P3 client `ForEach` (chips + suggestions), P4 `.keymap`/`commit`/`removeLast`/`commitValue` (the keyboard
// + click vocabulary), P5 `filter`/`count` (the suggestion list derives in-browser), P6 `.show` (suggestions
// appear while typing). A library component so apps write `TokenField(name:items:)`, not the assembly.
//
// No-JS fallback by construction: the whole thing is a `<form>` — without the runtime, typing + Enter
// submits the query to `action` (the server commits + re-renders); the committed chips are server-rendered
// from `selected`. With the runtime, the keymap intercepts Enter and commits client-side (no round-trip).

public struct TokenField: HTML {
    public let name: String
    public let items: [String]
    public let selected: [String]
    public let action: String

    /// A token field over `items` (the full suggestion set). `selected` seeds the committed chips (the
    /// server's current value); `action` is the no-JS commit route (the form's `action`).
    public init(name: String, items: [String], selected: [String] = [], action: String = "") {
        self.name = name
        self.items = items
        self.selected = selected
        self.action = action
    }

    public static func _render<Target: RenderTarget>(_ html: Self, into target: inout Target) {
        // Static / no-JS render (no ambient context): a plain form + text input — the server `action` commits.
        guard let context = ADHTMLRenderContext.child() else {
            Self.lower(html.staticForm, into: &target)
            return
        }
        // Interactive: the state cells register in this island's scope; the view binds to them.
        ADHTMLRenderContext.$current.withValue(context) {
            let arena = context.arena
            let query = arena.signal("")
            let tokens = arena.signal(html.selected)
            let allItems = arena.signal(html.items)
            let filtered = arena.computed(
                allItems.reactive.filter { $0.lowercased().contains(query.reactive.lowercased()) })
            let view = html.combobox(query: query, tokens: tokens, filtered: filtered)
            let scope = arena.cells(inScope: context.scope)
            target.islandOpen(
                id: IslandID("tf\(context.scope)"), on: .load, scope: scope, connect: nil, key: nil)
            Self.lower(view, into: &target)
            target.islandClose()
        }
    }

    /// Render a built `some HTML` view through its concrete type (the type is known at compile time).
    @inline(__always)
    private static func lower<V: HTML, Target: RenderTarget>(_ view: V, into target: inout Target) {
        V._render(view, into: &target)
    }

    /// The no-JS form: a single text input that posts the typed value to `action`.
    private var staticForm: some HTML {
        form {
            input().attribute("name", name).attribute("type", "text").attribute("autocomplete", "off")
        }
        .attribute("action", action).attribute("method", "post")
    }

    /// The interactive combobox, wired to its state cells.
    private func combobox(query: Signal<String>, tokens: Signal<[String]>, filtered: Computed<[String]>)
        -> some HTML
    {
        form {
            // Committed chips (client list over the tokens array).
            ul {
                ForEach(tokens) { item in li { item.text }.class("chip") }
            }
            .class("tokens")
            // The query input: two-way bound + keyboard-mapped (Enter commits, Backspace pops the last chip).
            input()
                .attribute("name", name)
                .attribute("type", "text")
                .attribute("autocomplete", "off")
                .model(query)
                .keymap([
                    ("Enter", Behavior.commit(tokens, from: query)),
                    ("Backspace", Behavior.removeLast(tokens))
                ])
            // Suggestions: the filtered list, shown only while typing; clicking one commits its text.
            ul {
                ForEach(filtered) { item in
                    li { item.text }.on(.click, Behavior.commitValue(tokens, clearing: query))
                }
            }
            .class("suggestions")
            .show(when: query.reactive.count > 0)
        }
        .attribute("action", action).attribute("method", "post")
    }
}
