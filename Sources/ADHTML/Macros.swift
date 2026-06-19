// ADHTML's macro declarations (implementations in the `ADHTMLMacros` plugin target). ADR-0008.

/// Compile-time-validated HTML attribute name. Emits a diagnostic if `name` is not a valid HTML
/// attribute token; otherwise expands to the literal. Use it where an attribute name should be checked
/// at compile time rather than trusted at runtime — e.g. `div {}.attribute(#attr("data-id"), value)`.
@freestanding(expression)
public macro attr(_ name: String) -> String =
    #externalMacro(module: "ADHTMLMacros", type: "AttributeNameMacro")
