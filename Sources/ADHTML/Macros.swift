// ADHTML's macro declarations (implementations in the `ADHTMLMacros` plugin target). ADR-0008.

/// Compile-time-validated HTML attribute name. Emits a diagnostic if `name` is not a valid HTML
/// attribute token; otherwise expands to the literal. Use it where an attribute name should be checked
/// at compile time rather than trusted at runtime — e.g. `div {}.attribute(#attr("data-id"), value)`.
@freestanding(expression)
public macro attr(_ name: String) -> String =
    #externalMacro(module: "ADHTMLMacros", type: "AttributeNameMacro")

/// Conform a type to ``Component`` — the SwiftUI-style marker for a composed view. Sugar for writing
/// `: Component`; pairs with ``State()`` for reactive components, e.g.
/// `@Component struct Counter { @State var count = 0; var body: some HTML { … } }`. Per-instance render
/// scoping (so each instance's state cells are distinct) is intrinsic to `Component`, so this only adds
/// the conformance.
@attached(extension, conformances: Component)
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
