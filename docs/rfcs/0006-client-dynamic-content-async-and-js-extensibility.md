# RFC 0006 — Client-side dynamic content, async/network interactions, and JavaScript extensibility

- **Status**: Research / Draft
- **Date**: 2026-06-20
- **Related**: RFC-0003 (reactivity/hydration/wire), ADR-0005 (islands), ADR-0006 (tiny JS runtime, no
  Swift→WASM), ADR-0007 (wire format), ADR-0012 (ADServe integration), RFC-0005 (authoring DSL).
- **Scope**: three areas the user called out — (I) client-side dynamic content, (II) async &
  network-dependent content + interactions, (III) JavaScript support/extensibility on the client. This is
  a research doc: it inventories what the 2.2 KiB runtime does today, the gaps, the design options with
  tradeoffs and prior art, and a recommended, phased architecture. It does **not** decide the final API
  (that becomes ADRs as each lands).

## 1. Motivation

ADHTML today does **resumable interactivity** well: server-rendered HTML + islands that wire fine-grained
signals, the closed `increment`/`toggle`/`set` behaviors, `data-adh-bind:*` bindings, client-recomputable
computeds, and an SSE `patch`/`morph` client. That covers local, self-contained interactivity. It does
**not yet** cover the three things real apps need next: content whose *shape* changes on the client
(show/hide, growing/shrinking lists), content that depends on the *network* (fetch, loading/error states,
forms, live push), and a sanctioned way to run *author JavaScript* (third-party widgets, custom logic)
without breaking the zero-inline-JS / CSP / ≤4 KiB-core posture. This RFC researches all three.

Guiding principle (inherited from ADR-0005/0006): **server-authoritative by default, minimal client.**
Prefer hypermedia (server returns HTML, client morphs) over shipping app logic to the browser; reach for
client JSON state only when the interaction is genuinely local; treat author JS as an opt-in, CSP-safe,
out-of-core extension.

## 2. What the client runtime does today (grounded)

`ClientRuntime/src/` — `signals.js` (fine-grained signals + batched scheduler), `behaviors.js` (closed
set), `wire.js` (parse inline state → signals; client-recomputable computeds via `expr.js`), `morph.js`
(id-aware DOM morph), `runtime.js` (`hydrate()` + document-delegated events + `data-adh-bind:*` +
`connect()` SSE). Capabilities:

- **Static→interactive** via islands + loading directives (`load`/`idle`/`visible`/`media`).
- **Local state mutation** through the closed `Behavior` set only (`increment`/`toggle`/`set`).
- **One-way bindings** `data-adh-bind:text|value|class` (signal → node).
- **Client-recomputed derived values** over the closed expr set (`+ - * ++`).
- **Server push** via `connect(url)`: SSE `patch` (set cells) + `morph` (swap an island's HTML). *Requires
  ADServe SSE — not yet available (ADR-0012).*

Gaps relevant here: no conditional show/hide, no dynamic/keyed list rendering from a cell, no client
`fetch`/async, no loading/error UX, no form/action handling, no author-JS extension point, no two-way
input binding, no event modifiers (debounce/preventDefault).

## 3. Area I — Client-side dynamic content

### 3.1 Conditional rendering (show/hide)
- **Today:** approximated by binding `class` and toggling CSS (`hidden`) via a signal.
- **Design:** a first-class `data-adh-show="<cell>"` binding (toggles `hidden`/`display` from a truthy
  cell) and/or `data-adh-bind:attr:<name>` for arbitrary boolean attributes (e.g. `disabled`, `aria-
  hidden`). Cheap, declarative, no template needed. (Recommended; ~10 LOC in the runtime.)
- **Branch swap** (`if/else` whose *both* arms exist): render both server-side, toggle visibility; or, for
  expensive arms, server `morph` on demand (Area II). Avoid client templating for simple cases.

### 3.2 Dynamic & keyed lists
The hard one. Three options, increasing client weight:
1. **Server morph (recommended default).** The list lives on the server; an interaction triggers a
   fragment fetch and `morph` swaps the `<ul>`. Reuses the existing id-aware `morph.js` (keyed reorder
   already works) and keeps zero list logic in the client. Needs ADServe endpoints (Area II). Best for
   CRUD lists, pagination, filtering, search results.
2. **Client list from an array cell + `<template>`.** Extend the wire with array-valued cells (today
   `WireValue` is scalars + arrays at the data level but cells are scalar — RFC-0003 notes object/array
   cells as a later addition) and a `data-adh-each="<cell>"` directive over a `<template>` row, with a key
   expression for keyed reconcile. This is the Alpine/Datastar `x-for` model. Heavier client; only worth
   it for purely-local lists (e.g. a client-only cart before checkout).
3. **Client template clone.** A `<template>` + a behavior that clones+binds a row. Lowest-level; likely
   folded into option 2.

**Recommendation:** ship 3.1 (show/hide) now; make **server morph** the default for dynamic lists
(pending ADServe); add array-cell `data-adh-each` only when a concrete local-list use case demands it.

### 3.3 Client templates / fragments
A `<template id>` registry the runtime can clone + bind is the substrate for 3.2 option 2 and for
optimistic UI (Area II). Keep it out of core until 3.2.2 is justified.

## 4. Area II — Async & network-dependent content + interactions

Two complementary models; ADHTML should support both, defaulting to hypermedia.

### 4.1 Hypermedia (htmx / Hotwire-Turbo style) — the recommended default
Declarative request → server returns an **HTML fragment** → client **morphs** it into a target.
- **Authoring (target DSL):** `button { "Load more" }.action(.get, "/items?page=2", swap: .morph, into: "#list")`
  → emits `data-adh-get="/items?page=2" data-adh-target="#list" data-adh-swap="morph"`.
- **Runtime:** a delegated handler issues `fetch`, reads the HTML, and calls the existing `morph()` on the
  target (or `innerHTML`/`beforebegin`/`afterend` swap styles). Triggers beyond click: `on: .submit`
  (forms), `.change`, `.load`, `.visible` (infinite scroll), `.every(ms)` (polling — works client-only,
  no SSE needed).
- **Why default:** server stays authoritative; reuses `morph.js`; tiny client addition; no client app
  logic; aligns with ADR-0005. **Needs ADServe** to serve fragments (`text/html`, ADR-0012 P0).

### 4.2 JSON state fetch (Datastar style) — for genuinely local/derived UI
`fetch` JSON → `patch` signals → bindings/computeds update. For client-owned state that doesn't map to a
server fragment (e.g. live form validation, a computed preview).
- **Authoring:** an async action that sets cells from a response, e.g. `.action(.get, "/api/price",
  patch: ["price": .number])`. Kept narrow (closed mapping) to stay a generic interpreter, not arbitrary
  JS.

### 4.3 Async UX states (cross-cutting, required for either model)
- **Loading / error / empty:** a request sets an ambient state on the target (`data-adh-state="loading|
  error|done"`) the author styles/binds against; an `into`-scoped spinner/skeleton. Inflight class on the
  trigger.
- **Optimistic updates:** apply a local change immediately, reconcile/rollback on response (uses 3.3
  templates / signal snapshot).
- **Robustness:** `AbortController` to cancel superseded requests; request **dedupe** + last-wins race
  handling; debounce/throttle (event modifiers, §5/Area III); retry/backoff policy; timeout.
- **Forms:** progressive enhancement — a normal `<form>` posts; with JS, intercept → `fetch` → swap; serialize
  via `FormData`. Validation errors return as a fragment morph (hypermedia) or field cells (JSON).

### 4.4 Live / push
- **SSE** `patch`/`morph` — implemented client-side (`connect()`), **blocked on ADServe** `text/event-
  stream` (ADR-0012). The primary live-update path.
- **WebSocket** — future; same `patch`/`morph` frame shapes over a duplex channel for bidirectional apps.
- **Polling** — `.every(ms)` hypermedia trigger works **today, client-only** (no server push needed); a
  pragmatic stopgap for "live-ish" until SSE lands.

### 4.5 Security (Area II)
- **CSRF** on state-changing requests (token via meta/header) — ADServe-coordinated.
- **SSRF / open-redirect**: request URLs are author-authored (same-origin by default); an allowlist for
  cross-origin. Response **content-type** checked before swap; **size caps**; never `eval` a response.
- **Response trust:** morphed HTML is server-authored and still escaped at the source; the client never
  executes `<script>` from a morph unless explicitly opted-in (and then nonce/SRI-gated, Area III).
- Most of 4.1/4.4 is **ADServe-gated** (fragments, SSE, CSP nonce, CSRF). 4.2/4.3/polling can prototype
  client-only against any JSON/HTML endpoint.

## 5. Area III — JavaScript extensibility on the client

The stance (ADR-0006) is **no author JS by default**: the runtime is a small *generic interpreter*, not a
per-app bundle, and there is **no inline JS** (CSP-friendly). The research question is how to let authors
add real JS *when needed* without abandoning that posture. A capability ladder, lowest-risk first:

1. **Custom behavior registry (recommended primary).** Authors register named behaviors in their *own*
   external module: `ADH.behavior("addToCart", (cell, params, el) => { … })`, referenced declaratively by
   `data-adh-on:click="addToCart#…"`. Extends the closed set without inline handlers; stays CSP-safe
   (external module, SRI+nonce); the core stays generic. The closed built-in set remains the default.
2. **Lifecycle hooks / mount points (recommended).** `data-adh-mount="chart"` → a registered
   `ADH.mount("chart", (el, ctx) => cleanup)` runs when the island wires (and `cleanup` on unmount/morph).
   This is the **third-party-widget** path: charts, maps, editors, date pickers, web components init. Plays
   with `IntersectionObserver` loading directives for lazy mounting.
3. **Web components / custom elements.** Author ships a custom element; ADHTML just renders `<my-widget>`;
   the element self-upgrades. Zero runtime support needed — document it as the framework-agnostic path.
   ADHTML islands and custom elements compose (an island can contain a custom element and vice-versa).
4. **Event modifiers** (small, high-value): `.on(.input.debounced(300))`, `.preventDefault`,
   `.stopPropagation`, `.once`, key filters (`.on(.keydown(.enter))`). Declarative, interpreted by the
   runtime — not author JS, but removes the most common reason authors reach for JS.
5. **Raw `<script type="module" src>` escape hatch.** Via `RawHTML`, for progressive enhancement; must be
   external (no inline), SRI-hashed, and nonce-tagged (CSP). The greppable, last-resort hatch.

### 5.1 Security & budget (Area III)
- **No `eval`, ever** — the computed evaluator (`expr.js`) is a closed AST interpreter, not `eval`;
  custom behaviors are *registered functions*, not strings. Inline handlers stay banned.
- **CSP**: per-request nonce on any author module (ADServe #6, ADR-0012); the core runtime stays SRI-
  pinned (ADR-0011). Custom behavior/mount modules are author-owned, separately SRI/nonce-gated.
- **Budget**: extensions are **opt-in, separate modules** loaded only on pages that use them — the core
  runtime stays ≤4 KiB (ADR-0006). The registry hooks (`ADH.behavior`/`ADH.mount`) add a few hundred bytes
  to core at most; the author code is not counted against the core budget.

## 6. Recommended architecture & sequencing

| Phase | Item | Needs ADServe? |
|---|---|---|
| 1 | `data-adh-show` + boolean/attr bindings (§3.1); event modifiers debounce/preventDefault/once (§5.4) | no |
| 2 | Custom behavior registry + mount/lifecycle hooks (§5.1–5.2); document web-components path (§5.3) | no |
| 3 | Hypermedia actions: `data-adh-get/post` + `target`/`swap` → `fetch` → `morph`; polling `.every` (§4.1, §4.3 states) | **yes** (fragments) for full use; polling/JSON prototype-able now |
| 4 | JSON fetch→cells (§4.2); optimistic UI + abort/dedupe (§4.3); forms (§4.4) | partial |
| 5 | SSE live `patch`/`morph` wired end-to-end (§4.4) | **yes** (SSE) |
| 6 | Array cells + `data-adh-each` client lists (§3.2.2) — only if a concrete local-list case demands it | no |

Phases 1–2 are pure client-runtime work, shippable now, and unlock most "dynamic content + JS" needs
without ADServe. Phases 3–5 are the network story and are largely ADServe-gated (tracked in
`docs/integration/adserve-requirements.md`).

## 7. Non-goals

- No `eval` / no inline event handlers (CSP). No arbitrary client templating language. No client-side
  router/VDOM/virtual-list in core (an opt-in module at most). No Swift→WASM (ADR-0006). The core runtime
  stays a small generic interpreter; author logic lives in opt-in, CSP-safe, out-of-core modules.

## 8. References

- htmx (hypermedia: triggers, swaps, targets), Hotwire **Turbo** (frames/streams), **Datastar** (SSE +
  signals), **Alpine** (`x-for`/`x-show`/modifiers), **Stimulus** (controllers/lifecycle), **Qwik**
  (resumability, lazy mount). RFC-0003 (wire), ADR-0006 (runtime stance), ADR-0012 (ADServe).
