# ADR 0016 — `Region`: the keyed, re-renderable unit

- **Status**: Accepted (implemented 2026-06-20)
- **Date**: 2026-06-20
- **Related**: RFC-0020 (§1.6); ADR-0005 (islands, scope = data-leak boundary); ADR-0015 (implicit
  islands, the `c<scope>` id); RFC-0019 (the `Action`/morph transport, reused UNCHANGED). Unblocks
  Tier-2 server-action closures (Track 3) and component-scoped assets (Track 4), which both re-render a
  `Region`.

## Context

The reactive transport (RFC-0019) morphs a target subtree to server-rendered HTML. A client `Action`
resolves its morph target by **`getElementById`** (`action.js` `perform`), while an SSE `morph` frame
resolves by **`querySelector("[data-adh-id]")`** (`runtime.js` `connect`). An implicit island
(ADR-0015) carries only `data-adh-id` and a **counter-inferred** id (`c<scope>`). Two problems follow:

1. **No `getElementById` target.** An island has no plain `id`, so an `Action` (even a default-targeted
   one — "the nearest `data-adh-id`") resolves a value that `getElementById` cannot find. Actions can't
   reliably morph an island.
2. **The id is not stable across renders.** A page-render and an independent fragment-render of the same
   subtree assign *different* `c<n>` ids (the subtree sits at a different scope index in each), so a
   fragment morph misses the element it should reconcile. This is the page↔fragment "twin" hazard: today
   you maintain two hand-written renderers and pray their ids line up.

A SwiftUI-grade model needs a first-class **named, re-renderable region** — one element that is both the
in-page node and the unit a re-render targets, with a key the author controls so the page and the
fragment agree.

## Decision

Add `Region(_ id: RegionID, on:scope:connect:) { … }` — a **thin, stably-keyed `Island`**. It lowers to
an island root that stamps its author-given key as **both** `data-adh-id` (the SSE-morph / wiring
selector) **and** a plain `id` (the `getElementById` target the action interpreter uses). It is a real
island in the wire, so the document-level delegated listener delivers events fired inside it, and an
inner `Action` with no explicit target **defaults to the region** (the runtime walks to the nearest
`data-adh-id`, now a resolvable `id`).

- **Author-given key, not inferred.** `RegionID` is a string-keyed value (`ExpressibleByStringLiteral`);
  apps name regions by extending it (`static let content = RegionID("content")` → `Region(.content)`).
  The same key labels the full-page render AND any fragment render, so an independent re-render morphs the
  SAME element. `.islandID` bridges the key into the shared island/`data-adh-id` space for `Action.target`.
- **Additive at the byte level.** The island opcode gains an optional `key: String?`; non-`nil` emits the
  plain `id`. `Island` and implicit islands pass `nil` and stay **byte-identical** (regression-tested).
- **Transport unchanged.** No `runtime.js` / `action.js` / `morph.js` change. The headline behaviour
  ("inner actions default their morph target to the region") is the *existing* default-target resolution
  finally landing on a resolvable `id`. Proven by a happy-dom test on the shipped runtime.
- **Scope like `Island`.** `scope` is the data-leak boundary, default empty (a pure morph anchor whose
  interactive children are their own islands). A region with bindings written *directly* in it passes the
  seed cells, exactly as `Island` does — `Region` deliberately does **not** add the implicit-island scope
  inference (its content is eager, like `Island`'s; inference stays a `@Component` feature).

## Consequences

- **Positive.** One named element is the re-render unit for client actions, SSE, boosted navigation
  (Track 2 P7), Tier-2 server actions (Track 3), and component-scoped assets (Track 4). The page↔fragment
  twin can collapse: render the `Region` once, re-render the same `Region` for a fragment response, and
  the stable key guarantees the morph lands. Actions inside a region "just work" with no `.target`.
- **Negative / risk.** A new island-opcode field touches every `islandOpen` site (opcode, both render
  targets, the byte writer, the two island-collection passes, `Island`/`Component`/`Region`). All are
  in-repo and mechanical; the `nil` default keeps existing output unchanged (guarded by a byte-exact
  regression test). A region nested inside a `@Component` island double-binds its bindings (both islands'
  `wireIsland` query the same nodes) — a pre-existing nested-island characteristic (idempotent writes),
  not introduced here; the idiomatic top-level `Region` (page-level re-render unit) avoids it.
- **Invariants kept.** Explicit `Island` still works and is byte-identical; static components stay
  zero-JS; escape-by-default (the key is attribute-escaped in both `id` and `data-adh-id`); the wire
  format and the RFC-0019 transport are unchanged; floor unchanged.
