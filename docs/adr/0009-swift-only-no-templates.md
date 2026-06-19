# ADR 0009 — Swift-only views: no template files; whole-scope compile-time type-checking

- **Status**: Proposed
- **Date**: 2026-06-19
- **Related**: RFC-0004; ADR-0002 (renderer), ADR-0004 (signals), ADR-0008 (macros)

## Context

The user requirement: *"Can the server rely on `.swift` files and no `.html` files, so the whole server
scope type-checks and compiles at all times?"* A template engine (Leaf/Mustache/.html) is a second,
untyped language evaluated at runtime — a renamed field, a typo'd variable, or a malformed tag is a
runtime error or silent wrong output, found in a browser, not by the compiler.

## Decision

ADHTML has **no template files** — views, components, and the client interactivity contract are all
`.swift`. The entire server scope (ADServe routing, handlers, read-models, the ADJSON API, ADHTML
views, and typed client behaviors) is **one SwiftPM build graph** that `swift build` type-checks and
compiles together. `swift build` is the template compiler. The compile-time-checked surface includes:

- **element/attribute legality** via phantom types + trait protocols (`href` on a `<div>` does not
  compile);
- **well-formed structure** via the result builder; void elements carry no children by type;
- **event→state bindings** via a closed, generic `Behavior<S>` enum (`.increment` on a `Signal<String>`
  does not compile; the runtime's interpreter switch is total);
- **HTML/attribute literals** via the `#html`/`#attr` macros (ADR-0008);
- **the wire payload** as a `WireEncodable` value graph serialized by `ADJSON` (never hand-built JSON).

The honest boundary: **~98% Swift-checked.** The irreducible non-checked surface is (1) the fixed
generic JS runtime (shipped once, browser-tested, ADR-0006) and (2) a rare, greppable
`RawClientScript`/WASM escape hatch for interactions outside the closed `Behavior` set. The wire
**version** is a runtime check (mitigated by a CI parity test).

## Consequences

- **Positive (coherency/consistency/integrity/reliability)**: whole classes of template bugs become
  compile errors; HTML and JSON adapters render from the same typed read model and cannot drift; a
  field rename breaks the build, not production; one language, one build, one watch loop.
- **Negative**: type-check/macro cost on view-heavy modules (bounded by ADR-0008 + the timing-flag
  gate); the escape hatch and the JS runtime remain outside the type-checker — kept rare and greppable
  so an audit can enumerate every un-checked byte.
- **Verification**: negative `// expected-error` fixtures prove illegal element/attribute combos and
  mistyped bindings fail to compile; a sample app target proves the whole scope builds as one unit.
