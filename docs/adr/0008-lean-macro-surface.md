# ADR 0008 — Lean macro surface

- **Status**: Accepted (implemented 2026-06-20)
- **Date**: 2026-06-19
- **Related**: RFC-0004; ADR-0009 (compile-time checking), ADR-0010 (packaging)
- **Implementation**: `#attr` (compile-time attribute validation), `@State` (peer macro adding a
  `<name>Signal` accessor backed by an ambient `ADHTMLRenderContext`), `@Component` (extension macro
  adding `Component` conformance; per-instance render scoping is intrinsic to `Component._render`). The
  surface stayed lean — no `#html` tokenizer macro yet (deferred). swift-syntax confined to the `.macro`
  target; built with `--build-system native`.

## Context

Swift macros (swift-syntax) can synthesize component boilerplate and validate HTML at compile time —
directly serving the "Swift-only, compile-time-checked" thesis (RFC-0004). But macros are the single
largest build-time cost in a Swift package and complicate the dependency graph (swift-syntax is heavy).
The prism asks for macros "where they earn their place" and for buildtime discipline.

## Decision

A **small, closed macro surface**, implemented only on the `.macro` target `ADHTMLMacros` (the sole
place swift-syntax appears; consumers of `ADHTML` resolve it but it never enters their runtime graph):

- `@Component` / `@HTMLComponent` — attached `member` + `extension` roles: synthesize the stable
  hydration id, the state encode/decode, and island registration for a component struct.
- `#html` / `#attr` — freestanding `expression` macros that validate HTML / attribute-name literals at
  expansion (a malformed literal is a compile error — RFC-0004 §1).
- island registration — attached `peer` where needed.

Use the `extension` role (not the deprecated `conformance` role). Keep the surface lean: four macros,
no speculative additions. The 100 ms type-check timing flags (ADR-0010) make a macro-induced
type-check regression a hard CI error.

In the initial pass `ADHTMLMacros` is a valid, compiling `CompilerPlugin` placeholder (no macros yet);
the macros above land with the reactivity subsystem. The target exists now so the graph and the
swift-syntax gating are locked.

## Consequences

- **Positive**: removes component boilerplate; moves HTML/attribute validation to compile time;
  swift-syntax is isolated to one target and never shipped to consumers.
- **Negative**: build-time cost (swift-syntax) and macro-maintenance — bounded by the lean surface and
  the timing-flag gate; benchmark macro-heavy vs hand-written modules if cost grows.
- `@dynamicMemberLookup` is used only where it genuinely improves ergonomics (e.g. typed environment
  access), never as a stringly back door that would defeat ADR-0009's compile-time guarantees.
