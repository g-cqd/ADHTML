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

## Build-system note — swiftbuild macro-in-test-bundle mislink (2026-06-20 investigation, RFC-0020)

The reason every build takes `--build-system native` is a **swiftbuild bug, not an ADHTML structuring
problem** — confirmed by isolating the failure on the pinned toolchain:

- **Libraries and executables build CLEAN under the default `swiftbuild` engine** (`swift build` →
  "Build complete!"; the `ADHTML` umbrella + its executables link fine).
- **Only TEST bundles fail.** `swift build --build-tests` under swiftbuild produces *undefined SwiftSyntax
  symbols* referenced from `ADHTMLMacros-…-testable.o` — i.e. swiftbuild links the macro **plugin** target
  into a test bundle (transitively, via the umbrella) as if it were an ordinary link-time dependency,
  without linking SwiftSyntax. A correct build links a `.macro` target into the *compiler* (a host
  plugin run at build time), never into a downstream test executable. The classic `native` engine does
  this correctly.

There is **no ADHTML-side restructure that fixes it**: the `.macro` declaration is already correct, and
any test that compiles macro-annotated code must run the plugin — the mislink is in how swiftbuild scopes
the plugin's link, not in the package shape. Tracked as an upstream swift-package-manager/swiftbuild issue;
drop `--build-system native` once fixed.

**Actionable consequence (narrows the prior "native everywhere"):** a *consumer* (e.g. the spare-parts
app) **can adopt the `@Component`/`Page` umbrella for `swift build` / `swift run` under the default build
system today** — the library it links builds clean. Only the consumer's **test targets that transitively
link the umbrella** need `--build-system native` (or can stay on the Foundation-free `ADHTMLCore`, which
carries no macro and builds tests clean under swiftbuild). This unblocks the RFC-0020 Tier-1 ergonomic
jump for the app's source/runtime without waiting on the toolchain fix.
