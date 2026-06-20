# ADR 0019 — Single-source wire-token vocabulary (Swift-generated, build-time mangled)

- **Status**: Accepted (implemented 2026-06-20)
- **Date**: 2026-06-20
- **Related**: ADR-0007 (wire format — the `data-adh-*` attributes this supersedes), ADR-0006 (the ≤ 4 KiB
  JS budget — the motivation), ADR-0009 (codegen convention, ADHTMLCodegen). User-directed.

## Context

The wire attributes were verbose (`data-adh-island`, `data-adh-bind:text`, …): they cost bytes in every
rendered page AND in the JS runtime (as selector literals), and the Swift renderer and JS runtime each
hard-coded them — a drift hazard. Measured: gzip already dedups the repeated `data-adh-` prefix, so naive
shortening saves only ~25–49 B in the runtime — but per-page HTML payload benefits more, and a single
source of truth removes the drift hazard outright. (The user weighed the tradeoff and chose maximal
density.)

## Decision

A **single, Swift-generated, build-time-mangled** wire-token vocabulary.

- **Source of truth: `wire-tokens.json`** — an ordered list of `[name, token]` pairs, in three closed
  categories (attribute names `T`, behavior values `B`, swap values `S`). Tokens are **single base36
  characters** (maximal density). The spec stays bare; the **generator applies the `data-` prefix to the
  attribute-name category only** (the one place it is applied) — so attribute names are valid HTML5 custom
  data attributes (`data-a`, `data-b`, …, compound `data-c:click`), while behavior/swap **values** stay
  bare (they are attribute values, not names: `data-c:click="a#0#1"`, `data-v="a"`). `class`/`id`/`style`
  keep their real names.
- **Generation is Swift-side, via a SwiftPM command plugin** (`generate-wire-tokens`, not a JS script):
  it regenerates BOTH `Sources/ADHTMLCore/Wire/WireTokens.swift` (the renderer's constants) and
  `ClientRuntime/src/tokens.js` (the runtime's constants) from the JSON, so they cannot drift. A command
  plugin (not a build plugin) → it never runs during a normal `swift build` and can't destabilize it.
  Run: `swift package --allow-writing-to-package-directory generate-wire-tokens`.
- **The Swift renderer routes through `WireToken.*`** (Bindings/Action/ForEach/AttributeStore); the island
  byte-writer keeps short literals on its perf path, pinned to the spec by a render parity test.
- **The JS runtime routes through `T.*`** (single source, readable). A **build-time mangling step**
  (`build.js` onLoad plugin) inlines every `T.<name>` to its 1-char literal before bundling, so the `T`
  object + its import tree-shake away — the readable source costs **zero** bytes in production. (`T` is a
  plain object literal, not `Object.freeze`, precisely so it tree-shakes once unused.)
- **Parity is tested both ways**: a Swift test pins `WireToken.all` + proves the renderer emits the tokens;
  a JS test asserts `tokens.js` deep-equals `wire-tokens.json`. A `regenerate + git diff` CI step guards
  against a stale committed generated file.

## Consequences

- **Positive.** One source of truth; Swift owns generation; the two runtimes can't drift (parity-tested).
  The runtime drops to 3.86 KiB (from 3.95) AND every rendered page is smaller; the readable `T.x` /
  `WireToken.x` source is free in the bundle (mangled out). Adding/renaming a token is a one-line JSON
  edit + regenerate.
- **Negative.** The wire is now cryptic in the DOM inspector (`<div a b="…" c="load">`) — a real
  debugging cost, accepted for density (the logical names live in `wire-tokens.json` + the generated
  constants). Single-char `.contains("token")` test checks needed care (they collide with common letters)
  — fixed to match attribute context. This **changes the wire contract** (supersedes ADR-0007's
  `data-adh-*`); apps re-render against the new tokens (no stable external consumers yet).
- **Invariants kept.** Closed set; escape-by-default; the RFC-0019 transport SHAPE is unchanged (only the
  attribute names shrank — values like verbs/swap/behaviors are a follow-up); budget gated.
