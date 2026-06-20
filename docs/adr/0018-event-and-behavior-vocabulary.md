# ADR 0018 — Extended event & behavior vocabulary (P1 / P4)

- **Status**: Accepted (implemented 2026-06-20); will be **extended** by Tier-2 server-action closures.
- **Date**: 2026-06-20
- **Related**: RFC-0021 (P1 two-way binding, P4 events/behaviors); ADR-0009 (the closed `Behavior` set +
  Swift↔JS parity); ADR-0005/0007 (`data-adh-*`). Feeds the P9 `TokenField` capstone.

## Context

Beyond toggling state (P2/P6), prototype parity (RFC-0021 §1) needs: a text field that *is* a piece of
state (S3 search-as-state, T2 query — `v-model`), keyboard-driven list navigation (T5), and a way to
commit/clear/pop a token list (T1–T8 combobox). The closed `Behavior` set was `increment`/`toggle`/`set`
only, none of which read the triggering element or move a bounded index, and there was no two-way input
binding nor an event key-filter / `preventDefault`.

## Decision

Grow the closed vocabulary on both sides together (a `Behavior.names` ↔ `BEHAVIOR_NAMES` parity list
joins the existing `BinaryOp`/`Action.methods` anchors), with a no-JS fallback throughout. No `eval`.

- **P1 — `.model(_ signal: Signal<String>)` → `data-adh-model="cell"` + the initial `value`.** Two-way:
  the client sets the cell on `input` and an effect writes the cell back to `element.value` (the `!==`
  guard avoids a caret jump on echo). The initial `value` attribute is the no-JS state. Targets
  `<input>`/`<textarea>`.
- **P4 — event refinements.** `.keys("Enter","ArrowDown")` → `data-adh-keys` filters a keyboard behavior
  by `event.key`; `.preventDefault()` / `.stopPropagation()` → `data-adh-prevent` / `data-adh-stop`,
  applied when the behavior fires. These ride the existing delegated listener (no new listeners).
- **P4 — four new behaviors**, each type-checked at the Swift call site:
  - `setFromValue(sig)` — set a string signal from the triggering element's `value` (the interpreter now
    receives the node);
  - `listMove(index, by:, within: count, wrap:)` — move an index bounded by a live `count` **cell**
    (a `Signal`/`Computed<Int>` — e.g. a filtered list's length), clamping or wrapping;
  - `commit(tokens, from: query)` — append the query's text to the `tokens` array and clear the query;
  - `removeLast(tokens)` — pop the last array element.
  The last two operate on **array cells** (`Signal<[String]>`), which the wire value model already
  supports (`WireValue.array`); no wire change was needed for P1/P4.

## Consequences

- **Positive.** A text field becomes first-class state; keyboard list navigation, token commit, and
  backspace-pop are all expressible in typed Swift with a no-JS fallback. The `node`-aware `applyBehavior`
  unlocks value-reading behaviors without per-element listeners. +271 B gzip (3.43 → 3.62 KiB).
- **Negative / limits.** `model` is `<input>`/`<textarea>` only (no `<select>` multi yet). `listMove`'s
  `count` must be a cell (a static list wraps its length in a `Signal<Int>`) — uniform but slightly
  verbose. Budget headroom after P1/P4 is ~390 B gzip; **P3/P5 will require trimming or a justified
  budget note** (anticipated by the plan).
- **Invariants kept.** Closed set, parity-tested (`Behavior.names`); raw-cell-id ref convention; escape +
  no-JS fallback; the RFC-0019 transport unchanged (optimistic `applyBehavior` just gained the node arg).
- **Forward.** Tier-2 server-action closures will add a server-committed counterpart to `commit` (a signed
  endpoint + `Region` re-render) under this same vocabulary umbrella; this ADR will be amended then.
