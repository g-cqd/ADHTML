# RFC 0004 — Whole-scope compile-time-checked SSR (Swift-only, no templates)

- **Status**: Proposed
- **Date**: 2026-06-19
- **Area**: Type-safety / developer experience / integrity
- **Depends on**: RFC-0002 (rendering), RFC-0003 (reactivity), ADR-0008 (macros), ADR-0009 (the decision)
- **Related**: ADR-0009 (Swift-only, no templates)

## Summary

ADHTML has **no template files** — no `.html`, `.leaf`, `.mustache`, or `.ejs`. Views, components, and
client behaviors are all `.swift`. Consequently the **entire server scope — routes, handlers,
read-models, the JSON API, the HTML views, and the client interactivity contract — is one SwiftPM
build graph that `swift build` type-checks and compiles together**. `swift build` is the template
compiler. This RFC states the claim, defines exactly where the "fully type-checked" boundary lies, and
shows how to keep that boundary as large as possible. It directly serves the prism axes *type safety,
coherency, consistency, integrity, reliability*.

## 1. The claim

A template engine is a second, untyped language evaluated at runtime: a typo in a Leaf/Mustache
variable, a missing field, or an invalid tag is a *runtime* error (or silent wrong output), discovered
in a browser, not by the compiler. ADHTML removes that language. Because a view is a Swift value:

- a missing read-model field is a **compile error** (the property doesn't exist);
- an invalid element/attribute combination is a **compile error** (phantom types, §3);
- a malformed HTML literal is a **compile error** (the `#html` macro validates during expansion,
  ADR-0008);
- an event handler bound to the wrong state type is a **compile error** (generic `Behavior`, §3).

The same use case renders to HTML (ADHTML) and to JSON (ADJSON) from the same read model — two typed
adapters, one source of truth, no logic fork and no untyped template in between.

## 2. What "one build graph" means

ADServe routing (`ADServeDSL`), the handlers, the domain/read-models, `ADJSON` (de/serialization), and
`ADHTML` (views + behaviors) are SwiftPM targets in one resolved graph. A single `swift build`:

- type-checks handler → read-model → view data flow end to end;
- runs the macros (component synthesis, HTML/attribute validation) at compile time;
- enforces `.v6` strict concurrency and warnings-as-error across the whole surface (ADR-0010).

There is no separate template-compile, template-lint, or template-watch step, and no class of "the
template referenced a field the handler renamed" bug.

## 3. The checked surface (how far it goes)

- **Element/attribute legality** — elements are phantom-typed (`HTMLElement<Tag: HTMLTag, …>`); trait
  protocols gate which attributes are valid on which element (e.g. `href` only where the tag conforms
  to `HasHref`). Putting `href` on a `<div>` does not compile.
- **HTML structure** — the result builder makes only well-formed nesting expressible; void elements
  carry no children by type.
- **Event→state bindings** — the client-behavior vocabulary is a **closed, generic `enum`**:
  `Behavior<S>` cases like `.increment(Signal<Int>, by: Int)` or `.set(Signal<S>, to: S)`. Binding
  `.increment` to a `Signal<String>` does not compile; the runtime's interpreter `switch` over the
  same closed set is **total**. Adding an interaction is a compile-time change on *both* sides at once.
- **Loading strategies** — `enum LoadStrategy { load, idle, visible, media(String) }`, not stringly.
- **The wire payload** — a `WireEncodable` value graph, type-checked, serialized by `ADJSON`; never
  hand-built JSON.
- **HTML/attribute literals** — `#html("…")` / `#attr("…")` macros validate at expansion (ADR-0008).

## 4. The honest boundary (~98%)

Two artifacts are non-Swift and not checked by the Swift type-checker — stated plainly so an audit can
enumerate them:

1. **The fixed generic JS runtime** (ADR-0006) — hand-written, shipped once (like `htmx.min.js`), not
   authored per app. Covered by browser smoke tests, not the type-checker.
2. **The explicit custom-client-logic escape hatch** — when an interaction falls outside the closed
   `Behavior` enum (a canvas editor, a third-party widget, heavy client compute), the author drops to
   a conspicuously-named `RawClientScript`/WASM-island hatch. It is *greppable and gated*, not
   type-checked against the DOM.

A third, runtime-only check: the server↔runtime wire **version** (`"v"`) is validated at runtime, not
compile time — mitigated by the version field and a CI test that the shipped runtime matches the
emitted version (RFC-0003 §7).

## 5. Maximizing the checked surface

- Keep `Behavior` **exhaustive**: every new client interaction is a new enum case plus a runtime
  interpreter arm, added together — the registry stays closed and total.
- Make `Signal`/`Computed` carry their value type so every binding is generic-checked.
- Forbid stringly attribute names outside `#attr`; route **all** JSON through `ADJSON` so the wire is
  never hand-assembled.
- The escape hatch is what remains — keep it rare, explicit, and greppable (`RawHTML`,
  `RawClientScript`) so a review can list every un-checked byte.

## 6. Consequences

- **Coherency/consistency** — one language, one build, one source of truth for view data; HTML and
  JSON adapters cannot drift.
- **Integrity/reliability** — whole classes of template bugs (undefined variable, type mismatch,
  malformed markup) become compile errors; refactors that rename a field break the build, not prod.
- **Cost** — macro/type-check time on view-heavy modules; bounded by the lean macro surface (ADR-0008)
  and the 100 ms type-check timing flags that make a regression a hard CI error (ADR-0010).

## 7. Verification

- A sample app target wires routes + handlers + read-models + JSON API + ADHTML views + typed
  behaviors into **one** `swift build`.
- Negative tests (`// expected-error` fixtures): `href` on a `<div>`, `.increment` on a
  `Signal<String>`, and a malformed `#html` literal each **fail to compile** (phantom-type and
  macro-diagnostic negative tests via `SwiftSyntaxMacrosTestSupport` / compiler `-verify`).
- A test enumerates `RawHTML`/`RawClientScript` usages (the escape-hatch inventory).

## References

[Swift result builders](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/advancedoperators/#Result-Builders) ·
[Swift macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) ·
[swift-syntax](https://github.com/swiftlang/swift-syntax) ·
[Elementary phantom-typed elements](https://github.com/elementary-swift/elementary).
