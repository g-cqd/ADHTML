// ADHTML's macro declarations (implementations in the `ADHTMLMacros` plugin target). ADR-0008.

/// Compile-time-validated HTML attribute name. Emits a diagnostic if `name` is not a valid HTML
/// attribute token; otherwise expands to the literal. Use it where an attribute name should be checked
/// at compile time rather than trusted at runtime — e.g. `div {}.attribute(#attr("data-id"), value)`.
@freestanding(expression)
public macro attr(_ name: String) -> String =
    #externalMacro(module: "ADHTMLMacros", type: "AttributeNameMacro")

/// Conform a type to the `Component` protocol (a SwiftUI-style marker for a composed view). A component with
/// ``State()`` / ``Bound()`` additionally AUTO-WRAPS its body in a
/// hydration island with an inferred scope, so you never write `Island`/`scope`/`.id`
/// (`@Component struct Counter { @State var count = 0; var body: some HTML { … } }` is a resumable
/// counter). A static component renders inline (no island, no JS). Per-instance render scoping is
/// intrinsic to the protocol default, so this only adds the conformance.
@attached(extension, conformances: Component, names: named(isIsland))
public macro Component() =
    #externalMacro(module: "ADHTMLMacros", type: "ComponentMacro")

/// Declare reactive component state: `@State var count = 0`. The property keeps holding the initial
/// value (the server-render default); the macro adds a peer `countSignal: Signal<Int>` — the handle
/// that `.bind(_:to:)` and `Behavior` factories target — resolved through the ambient
/// render context. Needs an explicit type or a literal initializer so the `Signal` type is known, and
/// the enclosing type should be a `Component`.
@attached(peer, names: suffixed(Signal))
public macro State() =
    #externalMacro(module: "ADHTMLMacros", type: "StateMacro")

/// Declare a client-recomputable derived value: `@Bound var inCart: Reactive<Bool> { qtySignal.reactive
/// > 0 }`. The property is a plain computed property returning a `Reactive` expression (built from the
/// component's ``State()`` signal peers in the closed operator DSL); the macro adds a peer
/// `inCartComputed: Computed<Bool>` — the REGISTERED handle that `.bind(_:to:)`,
/// `.show(when:)`, `When` and friends target. The derived cell serializes its formula as a
/// `WireExpr`, so the browser re-evaluates it reactively with no server round-trip (RFC-0005 §3.5,
/// ADR-0015 — the rename of the earlier `@Derived` proposal). Requires the explicit `Reactive<T>`
/// annotation (the value type `T` is otherwise unknowable), and the enclosing type should be a
/// `Component`. The derivation lives in the getter (not a `= …` initializer) so it can reference the
/// instance's signal peers.
@attached(peer, names: suffixed(Computed))
public macro Bound() =
    #externalMacro(module: "ADHTMLMacros", type: "BoundMacro")
