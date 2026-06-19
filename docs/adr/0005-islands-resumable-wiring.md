# ADR 0005 — Islands + resumable wiring

- **Status**: Proposed
- **Date**: 2026-06-19
- **Related**: RFC-0003; ADR-0004 (signals), ADR-0006 (runtime), ADR-0007 (wire format)

## Context

The Swift server renders HTML but cannot run JS server-side, so the hydration architecture must let
the *server emit interactivity as data*. Three options (RFC-0001 §1): full hydration (re-run component
code on the client — forces a duplicate JS view layer), whole-page resumability (Qwik — presumes an
optimizer that code-splits *your* component code, which doesn't exist here), and islands + resumable
wiring (Astro topology × Qwik mechanics).

## Decision

Adopt **opt-in islands with resumable wiring**. The static perimeter is plain Swift-rendered HTML with
zero JS. An island subtree carries a stable `data-adh-id`, a loading contract
`data-adh-on="load|idle|visible|media(...)"` (Astro's directive), listener wiring as attributes
(`data-adh-on:click="<behavior>#<cellRef>"` resolving to a **closed Swift `Behavior` enum**), and
declarative bindings (`data-adh-bind:*`). The runtime **resumes** (reads wiring + state, attaches one
delegated listener) — it never rebuilds the tree or replays view code. **Reject** full hydration and
whole-page resumability.

**Security-critical**: serialize **only state reachable from a declared island scope** (Marko's
allowlist). Server-global/non-island state is never emitted.

## Consequences

- **Positive**: near-zero baseline JS; interactivity is *data the server emits*, fitting a non-JS host;
  payload + data-leak both bounded by the island-scope allowlist; pairs with hypermedia for the
  non-island majority.
- **Negative**: authors mark islands explicitly (a deliberate performance/security contract, not
  automatic); getting the scope allowlist right is the subsystem's main risk — mitigated by a test
  that non-island state never reaches the wire (RFC-0003 §6/§8).
- **Failure-safe**: islands are additive; with the runtime absent, server HTML + hypermedia still work.
