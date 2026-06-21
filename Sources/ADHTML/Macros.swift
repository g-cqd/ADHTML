// ADHTML's macro declarations (implementations in the `ADHTMLMacros` plugin target). ADR-0008.

/// Compile-time-validated HTML attribute name. Emits a diagnostic if `name` is not a valid HTML
/// attribute token; otherwise expands to the literal. Use it where an attribute name should be checked
/// at compile time rather than trusted at runtime — e.g. `div {}.attribute(#attr("data-id"), value)`.
@freestanding(expression)
public macro attr(_ name: String) -> String =
    #externalMacro(module: "ADHTMLMacros", type: "AttributeNameMacro")

/// Conform a type to the `Component` protocol (a SwiftUI-style marker for a composed view). A component
/// with `@State` / ``Bound()`` additionally AUTO-WRAPS its body in a hydration island with an inferred
/// scope, so you never write `Island`/`scope`/`.id` (`@Component struct Counter { @State var count = 0;
/// var body: some HTML { … } }` is a resumable counter). A static component renders inline (no island, no
/// JS). Per-instance render scoping is intrinsic to the protocol default, so this only adds the conformance.
///
/// `@State` itself is a property wrapper (in `ADHTMLCore`, re-exported here): `count` is the value and
/// `$count` is the projected `Signal`. The `@Component` detection keys off the `@State` / `@Bound`
/// attribute names.
@attached(extension, conformances: Component, names: named(isIsland))
public macro Component() =
    #externalMacro(module: "ADHTMLMacros", type: "ComponentMacro")

/// Declare a client-recomputable derived value from `@State`: `@Bound var inCart: Bool { $qty > 0 }`. The
/// macro reads the getter's expression over the component's `$state` projections (in the closed operator
/// DSL) and adds a peer `inCartComputed: Computed<Bool>` — the REGISTERED handle that `.bind(_:to:)`,
/// `.show(when:)`, `When` and friends target. The derived cell serializes its formula as a `WireExpr`, so
/// the browser re-evaluates it reactively with no server round-trip (RFC-0005 §3.5, ADR-0015 — the rename
/// of the earlier `@Derived` proposal).
///
/// Two annotation forms are accepted: a value type (`: Bool`), where the macro rewrites each `$state`
/// reference into its reactive operand; or the explicit `: Reactive<T>` form, taken verbatim. The
/// derivation lives in the getter (not a `= …` initializer) so it can reference the instance's `$state`
/// projections; the enclosing type should be a `Component`.
@attached(peer, names: suffixed(Computed))
public macro Bound() =
    #externalMacro(module: "ADHTMLMacros", type: "BoundMacro")
