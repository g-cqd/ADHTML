# RFC 0001 — ADHTML: a reactive, hydratable Swift SSR engine

- **Status**: Proposed
- **Date**: 2026-06-19
- **Area**: Rendering / view layer / hydration
- **Depends on**: `ADFoundation` (ADFCore), `ADJSON` (wire serialization), `ADServe` (HTTP host)
- **Related**: spare-parts-app RFC-0018 (SSR & view layer), ADR-0044 (adopt Elementary — superseded by ADR-0001 here), ADR-0046 (ADServe view support); ADHTML ADR-0001…0012, RFC-0002/0003/0004

## Summary

ADHTML is a **Swift server-side rendering engine** that renders type-safe HTML to bytes and emits
**reactive, hydratable** documents — the first Swift HTML library to carry server render *and* client
hydration in one design. It is the deferred first-party `ADHtml` from spare-parts-app ADR-0044, now
justified by the reactive/hydratable requirement and by deep typing against the `AD*` family
(`ADJSON`, `ADServe`, `URLBuilder`).

One constraint frames the whole engine:

> **The SSR host is Swift (NIO); it cannot run JavaScript server-side.** Isomorphic JS SSR
> (Vue/React/Svelte) re-executes component code on the client to hydrate, which would force a *second*
> implementation of every view in JS/WASM. ADHTML instead renders HTML in Swift and ships **state + a
> tiny generic runtime** — the client never re-runs your view logic.

The result is a two-tier model: **static Swift-rendered HTML + hypermedia** for the CRUD majority, and
**opt-in resumable islands** (Astro island topology × Qwik serialization mechanics × Solid/Svelte-5
fine-grained signals) for the interactive minority, all over a hand-written **~2–6 KB** client
runtime. Because views are Swift (result builders + macros) with **no template files**, the entire
server scope type-checks and compiles as one unit (RFC-0004).

This RFC is the umbrella; RFC-0002 specifies the rendering core, RFC-0003 the reactivity/hydration
subsystem, RFC-0004 the whole-scope-compile thesis, and ADR-0001…0012 the discrete decisions.

## 1. The constraint that decides it

ADServe is a persistence-agnostic NIO engine whose handlers return `ResponseContent.raw(body:
[UInt8], contentType:, status:)` — bytes plus a content-type. To render the UI here we must produce
HTML *in Swift*. The three hydration architectures from the JS world map onto a Swift host as:

| Architecture | What it needs | Fit for a Swift host |
| --- | --- | --- |
| **Full hydration** (Vue/React/Svelte default) | Re-run component code on the client to rebuild the tree + attach listeners | ✗ Forces a duplicate JS/WASM view layer; worst case for bundle + TTI |
| **Whole-page resumability** (Qwik) | An optimizer that code-splits *your component code* into lazy chunks | ✗ There is no JS component layer to split — rendering lives in Swift |
| **Islands + resumable wiring** (Astro × Qwik mechanics) | Serialize listeners + state into the DOM; a generic client runtime interprets them | ✓ **Best** — the *server emits the wiring as data*; the client runtime is generic |

Islands + resumable wiring is the only model whose defining feature a non-JS server can natively do:
emit the wiring as data. See ADR-0005.

## 2. Why first-party, not Elementary

spare-parts-app ADR-0044 adopted [Elementary](https://github.com/elementary-swift/elementary) behind
a `ViewRenderer` port and **deferred** a first-party engine "unless AD*-family consistency or deep
ADJSON/URLBuilder typing demands it; if so, port Elementary's byte-writer + escape-by-default design."
Two things now meet that bar:

1. **Reactivity + hydration**: no Swift HTML library (Elementary, swift-html, Plot, HTMLKit, Ignite,
   Tokamak, swift-dom) renders server-side *and* hydrates the same markup on the client. Elementary's
   companion is htmx (server round-trip); Ignite emits canned JS; Tokamak is client-only (archived
   Jan 2026). The reactive/hydratable surface is genuinely unoccupied — ADR-0001.
2. **Deep AD\* typing**: wire-state serialization is `ADJSON`; island/cache IDs and escaping ride
   `ADFCore` (`XXH64`, `ASCII`, `PercentCoding`); the byte sink and asset safety ride `ADServe`
   (`sha256HexLower`, `pathHasTraversal`). A first-party engine shares these primitives instead of
   re-implementing them — ADR-0011.

We **port Elementary's proven foundations** (struct + phantom-`Tag` element model with zero `any`,
escape-by-default, byte-streaming writer, `consuming`/`Sendable` rigor) and go beyond on three axes:
an **iterative (non-recursive)** renderer (RFC-0002), **context-aware** escaping (ADR-0003), and the
**reactivity/hydration** layer (RFC-0003). ADR-0001 records the decision; ADR-0044 is superseded for
this codebase.

## 3. State of the art (survey)

**JS frameworks.** Reactivity is converging on fine-grained signals: SolidJS (run-once → surgical
updates), Svelte 5 runes (compile-time signals), Vue 3.6 Vapor (compiler → direct DOM updates) — all
abandoning the virtual DOM. Hydration is converging on *less of it*: React 19 RSC streams a typed
object graph (the Flight protocol: line-delimited rows with `$`-prefixed cross-references) and
hydrates only `use client` subtrees; Astro hydrates per-island on a `client:load|idle|visible|media`
contract; Marko 6 auto-detects the minimal interactive set and serializes only it; **Qwik** eliminates
hydration via *resumability* — listeners become attributes pointing at lazy code, state is one
index-deduped JSON blob, and a **~1 KB** delegated-listener loader is the entire upfront runtime.

**Swift HTML DSLs.** Elementary is the architectural baseline (byte-streaming `HTMLStreamWriter`,
escape-by-default, zero-`any` phantom-`Tag` model, Embedded-ready). HTMLKit has the most sophisticated
escaping (an `EscapeContext` taint model). None do client hydration/reactivity.

**Client runtime.** Compiling Swift→WASM for the runtime is not viable in 2026: standard SwiftWasm is
multi-MB; Embedded Swift reaches sub-400 KB only by dropping `String`; every DOM op crosses the
JS↔WASM boundary; Tokamak is archived and `carton` deprecated. A hand-written few-KB JS runtime wins
on bundle, cold-start, TTI, and DOM-access cost — ADR-0006.

(Citations in RFC-0003/ADR-0006: [Qwik resumable](https://qwik.dev/docs/concepts/resumable/),
[qwikloader](https://qwik.dev/docs/advanced/qwikloader/),
[Astro islands](https://docs.astro.build/en/concepts/islands/),
[Datastar](https://data-star.dev/), [Elementary](https://github.com/elementary-swift/elementary),
[Swift WebAssembly](https://github.com/swiftlang/swift/blob/main/docs/WebAssembly.md).)

## 4. Architecture

1. **Rendering core (RFC-0002, ADR-0002)** — a Swift result-builder DSL of phantom-typed elements
   (zero `any`) lowered to a **flat opcode program** and emitted by a single **iterative** loop to
   `[UInt8]` / a streaming byte-sink. No runtime recursion over the value tree → bounded native stack,
   no deep-input stack-overflow DoS, a `maxDepth` fail-safe.
2. **Escaping (ADR-0003)** — escape-by-default, **context-aware** (`text/attribute/url/css/
   scriptJSON`), chosen by the element/attribute *type*, not the author; URL-scheme allowlist; one
   greppable `RawHTML` hatch; built on `ADFCore` byte primitives; fuzzed.
3. **Reactivity (RFC-0003, ADR-0004)** — fine-grained serializable `Signal`/`Computed` cells (not
   `@Observable`), server-evaluated for the initial render and linearized to the wire.
4. **Hydration (RFC-0003, ADR-0005)** — opt-in **islands** with a `data-adh-on` loading contract and
   **resumable wiring**; only island-scope state is serialized (a data-leak guard).
5. **Wire format (RFC-0003, ADR-0007)** — island attributes + one inline
   `<script type="application/adh-state+json">` index-deduped graph serialized via `ADJSON`; server
   push via **SSE + JSON Merge Patch (RFC 7396)** + HTML morph / out-of-band swaps.
6. **Client runtime (ADR-0006)** — one hand-written **~2–6 KB** generic interpreter (delegated
   listener + signals + DOM binding + SSE morph), shipped once as an **SRI-hashed** static asset.

## 5. Products & packaging (ADR-0010)

Mirrors `ADJSON` exactly: a lean Foundation-free `ADHTMLCore` + an `ADHTML` umbrella + a `.macro`
`ADHTMLMacros`, with `ADHTMLNIO` / `ADHTMLMarkdown` / `ADHTMLSRI` / `ADHTMLObservability` /
`ADHTMLFuzz` **env-gated** so the default `swift build` graph stays minimal (core deps:
`OrderedCollections` + `ADFCore`; the macro target adds swift-syntax). Floor macOS 15 / iOS 18
(stdlib `Mutex`); adopt `Span` (back-deploys); defer `InlineArray`/`UTF8Span` (2025 SDK).

## 6. The prism

ADHTML is designed against an explicit lens, mapped here to where it is satisfied:

- **Performance / memory** — iterative opcode renderer, `ADFCore.ByteBufferPool`, `Span`, streaming
  TTFB, ordo-one p-percentile CI gates (RFC-0002, ADR-0002).
- **Security / failure-safe** — context-aware escaping + URL allowlist + fuzzing (ADR-0003),
  island-scope allowlist (ADR-0005), `maxDepth` fail-safe, SRI (ADR-0006), render-error → safe
  fallback. XSS is CWE-79 #1; output encoding is structural, not optional.
- **Type safety / coherency / integrity / reliability** — Swift-only whole-scope compile, phantom
  types, closed behavior enum (RFC-0004, ADR-0009).
- **Concurrency safety** — `.v6` strict mode, `Sendable` nodes, `consuming`/`sending`, `Mutex` pools.
- **Complexity / avoid recursion** — flat opcode walk + iterative two-pass wire serializer
  (ADR-0002/0007); cyclomatic budget enforced by SwiftLint.
- **CI / buildtime / runtime** — warnings-as-error, 100 ms type-check timing flags, lint/format,
  fuzz, benchmark gate, DocC (ADR-0010).
- **Swift-idiomatic design** — result builders, macros, `@dynamicMemberLookup` where it earns its
  place, DSL (ADR-0008).

## 7. Placement in the stack

ADHTML is the view adapter the spare-parts SSR/hypermedia stack sequences in: it renders read models
to HTML the same way the JSON API (RFC-0006 there) renders them to JSON — two adapters over the same
services. It depends on ADServe's `ResponseContent`; the streaming/SSE/static-asset transport it wants
is ADServe's ADR-0046 work, behind which the `ADHTMLNIO` adapter is sequenced (ADR-0012). Until that
lands, server-rendered pages/fragments already work via buffered `.raw(text/html)`.

## 8. Scope, non-goals, risks

- **Non-goals**: a Node SSR sidecar; embedding JS in Swift; Swift→WASM as the baseline client runtime;
  a virtual DOM; template files of any kind.
- **Risks**: the reactivity/hydration subsystem is novel (over-serialize → data leak; under-serialize
  → broken hydrate) — RFC-0003 is the large review surface, mitigated by the island-scope allowlist
  and a test that non-island state never reaches the wire. ADServe ADR-0046 is a prerequisite for the
  full transport — mitigated by the buffered fallback. Pre-1.0 throughout.

## 9. Verification

- A page and its JSON twin render from the same application service + read model (no logic fork).
- Output is XSS-safe by construction (escape-by-default per context; fuzz the escaper; OWASP vectors
  render inert).
- An island resumes and updates with no full-tree hydration; non-island state never appears in any
  wire payload (test).
- The whole server scope compiles as one `swift build`; illegal element/attribute combinations fail to
  compile (negative tests) — RFC-0004.
- Render throughput / allocations / p50-p99 gated by the ordo-one suite; the client runtime stays
  ≤ 6 KB gzipped.

## References

[Elementary](https://github.com/elementary-swift/elementary) ·
[Qwik resumability](https://qwik.dev/docs/concepts/resumable/) ·
[Astro islands](https://docs.astro.build/en/concepts/islands/) ·
[Datastar](https://data-star.dev/) · [htmx](https://htmx.org/) ·
[React Server Components](https://react.dev/reference/rsc/server-components) ·
[Swift WebAssembly](https://github.com/swiftlang/swift/blob/main/docs/WebAssembly.md) ·
spare-parts-app RFC-0018 / ADR-0044 / ADR-0046.
