# ADR 0014 — Typed attribute value enums (preset HTML value sets)

- **Status**: Accepted (implementing 2026-06-20)
- **Date**: 2026-06-20
- **Related**: RFC-0005 (§3.1); ADR-0009 (compile-time legality), ADR-0008 (lean macro surface,
  `@dynamicMemberLookup` rejected), ADR-0013 (consuming modifiers); mirrors the existing
  `BindTarget`/`LoadStrategy` enum-modifier pattern.
- **Implementation**: a new `Sources/ADHTMLCore/DOM/AttributeValues.swift` adding `enum`s + gated
  `consuming` modifier overloads; no codegen change (per-element overloads via `where Tag == Tags.X`);
  purely additive (every existing `String` modifier stays).

## Context

ADHTML already enforces attribute *legality* at compile time (phantom-`Tag` + trait protocols — `.href`
on `<div>` is a compile error). But attribute **values** are stringly-typed: `target("_blank")`,
`rel("noopener")`, `method("get")`, `type("email")`, and — for attributes with no modifier at all —
`loading` / `crossorigin` / `scope` / `kind` set through the raw `.attribute(_:_:)` hatch. A great many of
these have a **fixed, never-changing value set** defined by the HTML/ARIA specs. Stringly-typing them
means typos compile, there is no autocomplete, and authors must memorize the valid tokens — cognitive
load and a correctness hazard, with no offsetting benefit. Separately, only two boolean attributes
(`hidden`, `disabled`) have modifiers; the rest (`required`, `checked`, `selected`, …) require the
error-prone `.attribute("required","")`.

## Decision

Model every fixed-value attribute as a Swift type and expose a gated, `consuming` modifier overload:

1. **`enum X: String, Sendable`** for each closed value set; `rawValue` is the HTML token (custom where
   needed, e.g. `_blank`, `datetime-local`). The modifier forwards to `attribute(name, x.rawValue, …)`,
   keeping the existing escape **context** (URL/CSS plumbing unchanged; enum values are known-safe ASCII).
2. **Legality is preserved exactly.** Where a trait already exists (`HasTarget`, `HasRel`, `HasMethod`,
   `HasType`), the typed overload is gated by it. For attributes shared across elements with *different*
   value sets (the `type` attribute) or with no trait yet (`loading`, `decoding`, `crossorigin`,
   `referrerpolicy`, `fetchpriority`, `scope`, `kind`, `wrap`, `enctype`, `as`, `preload`), gate with a
   **per-element** constraint `where Tag == Tags.X`. This keeps compile-time legality without a codegen
   change; multi-element attributes get one thin overload per legal element.
3. **Keep an escape hatch.** Every typed modifier coexists with the existing `String` overload (overload
   resolution picks the enum when an enum case is passed); `target` also gains `target(frame:)` for named
   frames. Authors can always reach an author-defined / future token.
4. **Per-element `type`.** `HasType` spans `<input>`/`<button>`/`<ol>`/`<script>`/`<link>`/… with disjoint
   value sets, so add `type(InputType)`, `type(ButtonType)`, `type(OrderedListType)` as per-element
   overloads alongside the generic `type(String)` (kept for MIME-typed elements).
5. **Typed ARIA = the first accessibility surface.** `role(Role)` (the ~70 WAI-ARIA roles) plus typed
   `aria-*` helpers (`ariaLive`, `ariaCurrent`, `ariaExpanded`, `ariaHidden`, `ariaChecked`, …). These
   replace `role(String)`/`aria(_:_:)` for the common cases (both retained).
6. **Boolean-attribute coverage.** Add `Bool`-typed (present-when-true) modifiers matching the
   `hidden`/`disabled` shape for `required`, `checked`, `selected`, `readonly`, `multiple`, `autofocus`,
   `open`, `novalidate`, `async`, `defer`, `controls`, `loop`, `muted`, `autoplay`, `playsinline`,
   `inert`, gated per-element. Tri-state "looks boolean but isn't" attributes (`draggable`, `spellcheck`,
   `contenteditable`) take a `Bool`/enum that emits `"true"`/`"false"` — preventing the bare-token bug.

## Consequences

- **Positive:** typos become compile errors; autocomplete surfaces the valid set; cognitive load drops;
  no added cyclomatic complexity (an enum `rawValue` replaces a string literal); typed ARIA gives the
  project its first real a11y surface. Fully additive — no call site breaks.
- **Negative / cost:** some repetition — a multi-element attribute (e.g. `crossorigin` on five elements)
  is one one-liner per element. Accepted to avoid a codegen pass now; if the repetition grows, these can
  migrate to generated trait conformances later (the generator already assigns traits per element).
- **No JS parity needed** — these are pure HTML output attributes (unlike `Behavior`/`BinaryOp`, which
  have JS-side parity tests). Tests assert the rendered bytes for each enum case + that the `String`
  escape hatch still works.
- **Invariants kept:** zero `any`, escape-by-default (context unchanged), `consuming` chains, floor
  unchanged.
