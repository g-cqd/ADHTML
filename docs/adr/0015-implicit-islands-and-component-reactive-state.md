# ADR 0015 — Implicit islands & component-level reactive state

- **Status**: Accepted (phased implementation)
- **Date**: 2026-06-20
- **Related**: RFC-0005 (§3.0, §3.0b, §3.2); ADR-0005 (islands, scope = data-leak boundary), ADR-0004
  (serializable signals), ADR-0008 (macros), RFC-0003 (wire format, stable `CellID`).
- **Implementation (phased)**:
  - *Phase A (additive, low-risk):* typed DOM events (`DOMEvent`) + `Signal`/`Computed` overloads of
    `.bind`/`.on` so the `.id` ceremony disappears. No engine change.
  - *Phase B:* island **scope inference** — the render context records cells touched per scope; `Island`
    defaults `scope` to that set (explicit `scope:` becomes an override).
  - *Phase C (the headline):* **implicit islands** — an interactive `@Component` auto-wraps as an island
    with an inferred scope and a stable id; the author never writes `Island(...)`.
  - *Phase D:* **`@Derived`** component computeds + a wider client expression set; explicit
    `serverComputed` for the opaque path.

## Context

Today an author makes a component interactive by hand: wrap a subtree in `Island("id", scope: [a.id,
b.id]) { … }`, wire events with stringly-typed names (`.on("click", …)`), and pass raw cell ids to
`.bind(.text, to: sig.id)`. Three problems compound (RFC-0005 §2): the `scope:` allowlist is the
subsystem's stated #1 hazard (omit a cell → it silently never hydrates); one piece of state is spelled
three ways (`count` / `countSignal` / `countSignal.id`); and there is **no** component-level computed
(derived state must drop to the arena, which `@Component` can't reach). The "Island" concept leaks into
every interactive view — the opposite of a SwiftUI-grade model where you think only in state and views.

## Decision

Make **"interactive component"** the authoring unit and **"island"** an inferred implementation detail.

- **Phase A — drop the ceremony (additive).** Add `enum DOMEvent` (`click`/`input`/`change`/`submit`/…
  + `.custom(String)`) with `.on(_ event: DOMEvent, _:)`; add `.bind(_:to: Signal)` / `.bind(_:to:
  Computed)` overloads. The `String`/`CellID` forms stay. Pure ergonomics, no engine change.

- **Phase B — infer island scope.** `ADHTMLRenderContext` tracks, per render scope, the set of `CellID`s
  touched by `.bind`/`.on`/`Reactive` during lowering. `Island` with no explicit `scope:` defaults to
  that set (union with any explicit ids). Removes the #1 hazard and the boilerplate; explicit `scope:`
  remains for the rare manual case.

- **Phase C — implicit islands.** `@Component` inspects its members at expansion: a type with `@State`/
  `@Derived` conforms to a marker `Interactive`. `Component._render` wraps an `Interactive` component's
  body in island markup automatically — **id** = hash of the render-scope path (the stable `CellID`
  scheme, RFC-0003 §2; also unblocks SSE morph targeting), **scope** = inferred (Phase B), **loading** =
  `.load` by default, overridable via `@Component(hydrate: .visible)` or a `.hydration(_)` use-site
  modifier. A component with no reactive members renders **inline** (no island, no JS) — the two-tier
  model, now inferred. Explicit `Island(...)` stays as a low-level escape hatch. Nested interactive
  components compose into nested islands because each instance already gets a fresh scope
  (`HTML.swift:23-36`).

- **Phase D — computed/derived in components.** `@Derived var total = $apples + $oranges` builds a
  client-recomputable `Reactive` and exposes a `Computed` handle usable in `.bind`. Widen
  `WireExpr`/`BinaryOp` (and the JS evaluator, with the parity test) to add `/`, comparisons, boolean
  ops, and a ternary, so more derived values stay client-reactive. Rename the opaque closure path to
  `serverComputed { }` so crossing into server-only is explicit, not silent. Aspirationally, a macro form
  `@Derived var total: Int { apples + oranges }` parses the body into a `WireExpr` (closed op set;
  out-of-set bodies diagnose or opt into `serverComputed`).

## Consequences

- **Positive:** developer-facing interactive code becomes `@State` + `@Derived` + events + bindings with
  **no `Island`, no `scope`, no `.id`** — SwiftUI-grade. The data-leak boundary is computed by the engine
  (inference is *at least* as safe as a hand-written allowlist, and removes the omission hazard). Stable
  ids unblock SSE morph. Phases A/B ship value immediately and de-risk C/D.
- **Negative / risk:** Phase C changes how islands enter the wire (collected from interactive components,
  not only explicit `Island` nodes) — the wire serializer must union explicit + implicit islands; covered
  by tests (data-leak test extended to implicit scope). Stable-id hashing must be deterministic across
  identical renders (already a Phase-1 `CellID` property). Inference must not *under*-scope (a referenced
  cell missing from the wire) — tested by round-tripping every component's referenced cells.
- **Invariants kept:** explicit `Island` still works; static components stay zero-JS; escape-by-default;
  zero `any`; floor unchanged. The closed `Behavior` set and the JS-parity discipline are preserved
  (Phase D extends the op set on both sides together).
