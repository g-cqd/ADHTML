// ADHTML's macro declarations (implementations in the `ADHTMLMacros` plugin target). ADR-0008.

/// Compile-time-validated HTML attribute name. Emits a diagnostic if `name` is not a valid HTML
/// attribute token; otherwise expands to the literal. Use it where an attribute name should be checked
/// at compile time rather than trusted at runtime — e.g. `div {}.attribute(#attr("data-id"), value)`.
@freestanding(expression)
public macro attr(_ name: String) -> String =
    #externalMacro(module: "ADHTMLMacros", type: "AttributeNameMacro")

/// Conform a type to ``Component`` (SwiftUI-style marker for a composed view), or to
/// ``InteractiveComponent`` when it has ``State()``/``Derived()`` — then it AUTO-WRAPS its body in a
/// hydration island with an inferred scope, so you never write `Island`/`scope`/`.id`
/// (`@Component struct Counter { @State var count = 0; var body: some HTML { … } }` is a resumable
/// counter). A static component renders inline (no island, no JS). Per-instance render scoping is
/// intrinsic to the protocol default, so this only adds the conformance.
@attached(extension, conformances: Component, names: named(isIsland))
public macro Component() =
    #externalMacro(module: "ADHTMLMacros", type: "ComponentMacro")

/// Declare reactive component state: `@State var count = 0`. The property keeps holding the initial
/// value (the server-render default); the macro adds a peer `countSignal: Signal<Int>` — the handle
/// that ``HTMLElement/bind(_:to:)`` and ``Behavior`` factories target — resolved through the ambient
/// render context. Needs an explicit type or a literal initializer so the `Signal` type is known, and
/// the enclosing type should be a ``Component``.
@attached(peer, names: suffixed(Signal))
public macro State() =
    #externalMacro(module: "ADHTMLMacros", type: "StateMacro")
