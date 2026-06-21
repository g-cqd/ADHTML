# RFC 0008 — Vue-style client components: component-issued XHR/WebSocket and client-reactive state

- **Status**: Research / Draft (design-first; awaiting approval before implementation)
- **Date**: 2026-06-21
- **Related**: RFC-0003 (reactivity/hydration/wire), RFC-0006 (client dynamic content — this RFC **evolves
  its stance**), ADR-0005 (islands / data-leak boundary), ADR-0006 (tiny generic JS runtime, no Swift→WASM),
  ADR-0012 (ADServe integration), the RFC-0019 action/morph contract (`ADHTMLActions`), ADServe `WS`/`Stream`
  DSL. Informed by the 2026-06-21 `Static` path-traversal audit (the *mediated network primitive* principle).
- **Scope**: a single decision and its API surface — let a Swift `@Component` **own client-side reactive
  state** and **issue its own XHR and WebSocket requests**, so ADHTML reads "more like Vue than Qwik"
  *without* discarding the resumable engine. Covers the client runtime, the Swift authoring surface, and the
  ADServe endpoints/contract required. Research doc: it fixes the architecture + phasing; the concrete macro
  and wire signatures become ADRs as each phase lands.

## 1. Motivation

RFC-0006 chose **server-authoritative by default, minimal client**: hypermedia (server returns HTML, the
client morphs it) is the default; client JSON state is for "genuinely local" interactions; author JS is an
opt-in, out-of-core escape hatch. That is a Qwik/htmx posture — the browser *resumes* a serialized graph and
rarely runs component logic.

The requested direction is **Vue-ward**: components should be *alive* in the browser — hold local reactive
state, run a `setup`/lifecycle, **fetch their own data (XHR)** on mount, and **subscribe to WebSockets** for
live updates, re-rendering fine-grained as state changes. Hypermedia stays a first-class option; it is no
longer the *only* sanctioned way for a component to reach the network.

Crucially, this is **not** a rewrite of the reactive core. The browser already has a Vue-grade reactive
system (`ClientRuntime/src/signals.js`: push-pull `Signal`/`Effect`, batched scheduler — finer-grained than
Vue's VDOM, closer to Solid). The gap is the **execution & authoring model**, plus two missing network
primitives. This RFC closes that gap as a **hybrid**: the resumable engine and islands stay; a client
component layer is added on top.

## 2. Decision (the chosen fork)

**Hybrid.** Keep the resumable engine + islands + hypermedia. Add a **client component layer** in two tiers:

- **Tier 1 — declarative data sources (no hand-written JS).** Swift primitives — a `Resource` (fetch-on-mount,
  with loading/error/value) and a `Channel`/`WebSocketSource` (subscribe → messages) — that bind into signals
  and re-render through the existing fine-grained effects. The *one generic runtime* interprets them; the
  author writes Swift, never JS. This is the 90% path and stays true to the project's "flexible, so we don't
  write JavaScript manually" goal.
- **Tier 2 — expanded client `ctx` (the escape hatch).** For a genuinely bespoke widget, the Track-4 mount
  bridge (`ClientRuntime/src/mount.js`) grows from today's `{ root, action }` into a small Vue-like surface:
  `ref`/`computed`/`effect`/`watch` (re-exported from `signals.js`), `onMounted`/`onUnmounted`, and **two new
  network primitives `ctx.fetch` (arbitrary JSON XHR) and `ctx.ws` (a managed WebSocket)**. Author logic still
  lives in an opt-in, CSP-safe, SRI-pinned external module — not inline, not `eval`.

Delivery is **design-first**: this RFC, then ADRs + implementation per phase (§10).

## 3. What exists today (grounded)

- **Reactive core — already Vue-grade.** `signals.js`: `Signal.get/peek/set`, dependency-tracking `Effect`,
  a synchronous batched+deduped scheduler. This is the substrate; `ref`/`computed`/`watch` are thin wrappers.
- **Hypermedia / morph.** `action.js` (`data-adh-action` → `fetch` with `ADH-Request: 1` → swap), `morph.js`
  (id-aware reconcile), `boost.js` (link/form boosting). The shared `request()` core (`action.js:85`) is
  HTML-morph-shaped: it `fetch`es and feeds the response to `applySwap` — there is **no JSON path**.
- **Component mount seed.** `mount.js`: `[data-component]` roots run a registered fn with `ctx = { root,
  action }`, returning an optional teardown (the effect/unmount pattern). `action` is the *only* network
  primitive and is hard-wired to the signed RFC-0019 morph endpoint — **no arbitrary XHR, no WebSocket.**
- **Resume / wire.** `wire.js` parses inline `adh-state` and reconstructs bindings without re-running
  component code (resumability). Islands (`ADR-0005`) are the serialization + data-leak boundary.
- **Server.** ADServe has `WS(_:)` (HTTP/1 upgrade → `WebSocketConnection`) and `Stream(_:)` (back-pressured
  upload) in `ServerDSL.swift`, plus the JSON verbs (`GET/POST/PATCH/DELETE` → `ctx.json`). There is **no
  client consumer of `WS` in the runtime**, and **no component-facing typed channel contract**.
- **Prior research.** RFC-0006 §4.4 lists WebSocket as "future; same `patch`/`morph` frame shapes over a
  duplex channel," and §5 lists the mount/behavior extensibility ladder. This RFC promotes that future to a
  concrete, Vue-shaped design.

**The gap, precisely:** (a) no client WebSocket primitive; (b) no arbitrary-JSON XHR from a component (only
the signed HTML-morph endpoint); (c) `ctx` too thin to author a reactive widget; (d) no Swift surface for a
component to *declare* a data source or channel bound to its state; (e) ADServe lacks the cross-origin (CORS)
and typed-channel ergonomics a component-issued request needs.

## 4. The model

### 4.1 Reactive primitives (reuse `signals.js`)
Expose, in the runtime's public surface, `ref(v)` (a `Signal`), `computed(fn)`, `effect(fn)`, and
`watch(src, cb)` — all thin over the existing core. No new reactivity engine. DOM updates remain fine-grained
effects (no VDOM in core; §11 non-goal).

### 4.2 Tier 1 — declarative data sources (Swift, no JS)
Two new authoring primitives, each serialized to a new wire cell kind the generic runtime drives:

- **`Resource`** — a fetch-on-trigger source. Conceptually: `Resource(get: "/api/parts", as: [Part].self,
  trigger: .mount)` yields three cells the view binds against: `value`, `isLoading`, `error`. The runtime
  opens the `fetch`, parses JSON, and `set`s the cells; bindings/`.show(when:)`/lists re-render. Triggers:
  `.mount`, `.visible`, `.every(ms)` (polling — already viable client-only), `.on(event)`. State-changing
  variants (`post`/`patch`/`delete`) carry the CSRF token (§8).
- **`Channel` / `WebSocketSource`** — a live source. `Channel("/ws/parts", as: PartEvent.self)` yields a
  `messages` signal (latest), a `status` signal (`connecting|open|closed`), and a `send` capability. Incoming
  frames `set` the cells → fine-grained re-render. Reconnect/backoff/heartbeat live in the runtime (§6), not
  the author's code.

Both bind to `@State`/`shared(key:)` cells, so a `Resource`'s `value` or a `Channel`'s `messages` is just
another reactive dependency of the existing view DSL (`.show`, `.bind`, list rendering). **No JS authored.**

### 4.3 Tier 2 — the expanded client `ctx` (escape hatch)
`mount.js`'s `ctx` grows (kept lean; opt-in module, not core budget):

```
ctx = {
  root,                              // the mount element (today)
  action,                           // signed RFC-0019 morph endpoint (today, unchanged)
  ref, computed, effect, watch,     // reactive primitives (re-export signals.js)
  onMounted, onUnmounted,           // lifecycle (onUnmounted = the returned teardown, today)
  fetch(url, opts),                 // NEW: arbitrary same-origin/allowlisted JSON XHR (AbortController-managed)
  ws(url, opts),                    // NEW: a managed WebSocket (reconnect/backoff/heartbeat/size-cap)
}
```

This is the Vue `setup(props, { ... })` analogue: a widget builds reactive state, fetches, subscribes, and
returns teardown. It remains an SRI-pinned external module (ADR-0006 / ADR-0011), never inline.

### 4.4 Component lifecycle & hydration (Vue-like)
A client component instantiates against its SSR-rendered DOM (`[data-component]` root), runs its Tier-1
sources / Tier-2 `setup`, attaches effects to existing nodes (no re-render of static markup), and tears down
on morph/unmount (`runCleanups`, `mount.js:26`). The server still renders the initial HTML (SSR + resume for
the static parts); the client owns only the *dynamic* state it declared — preserving the data-leak boundary
(a component's fetched state is owned by its island scope, never leaked across islands).

## 5. ADServe API additions

- **CORS for component XHR.** spare-parts proves the shape: the web app (`:webPort`) and the JSON API
  (`:apiPort`) are *different origins*. A component fetching `/api/...` is cross-origin → governed by CORS.
  **Correction (verified iter #3):** ADServe **already ships a `CORS` middleware** (`Middleware.swift:111`)
  that decorates responses with `Allow-Origin` and owns the OPTIONS preflight (both covered by tests). So this
  is not a missing surface — Phase 1 only wants ergonomic sugar (e.g. `App(cors:)`) over the existing
  middleware, plus an explicit origin allowlist + credentials policy for the cross-port case.
- **Typed WebSocket channel.** `WS(_:)` exists but is raw. Add a component-facing **`Channel`** ergonomic: a
  typed message contract (`Codable` in/out), an `origin`/auth check at upgrade, a broadcast/pub-sub helper for
  live fan-out (one mutation → push to subscribed sockets), and back-pressure bounds. The frame shape reuses
  RFC-0006's `patch`/`morph` vocabulary where it maps cleanly, plus typed JSON for app events.
- **Signed vs arbitrary.** Two network lanes stay distinct: (1) the **signed RFC-0019 morph** endpoint for
  HTML fragments (unchanged, CSRF-bound); (2) **component JSON XHR/WS** against the app's own API, guarded by
  CORS + CSRF (state-changing) + the API's existing auth. The runtime never invents a third, unmediated lane.
- **Fragment + JSON duality.** Handlers already branch on `ctx.isFragment` (RFC-0019). Extend the pattern: a
  route can serve HTML morph *or* JSON to the same component depending on `Accept`/`ADH-Request`.

## 6. Client runtime additions

- **`ws.js`** — a managed WebSocket: connect, JSON encode/decode, **reconnect with exponential backoff + jitter**,
  heartbeat/idle-timeout, an inbound **message size cap** (mirroring `action.js:20`'s `MAX_RESPONSE_CHARS`),
  and teardown on unmount. Never throws out of a handler (same guard discipline as `wireIsland`/`runAction`).
- **Generalized request core** — factor `action.js`'s `request()` into a transport that supports a **JSON
  mode** (parse + return a value) alongside the existing HTML-morph mode, with `AbortController`, request
  **dedupe / last-wins**, and timeout (RFC-0006 §4.3 robustness). `ctx.fetch` and `Resource` share it.
- **Budget.** The core posture is ≤~5 KiB (ADR-0006). `ws.js`, the JSON transport, and the Tier-2 `ctx`
  extensions ship as **opt-in modules** loaded only on pages that use them; the resumable core stays small.
  A page that never declares a `Resource`/`Channel` pays nothing.

## 7. Swift authoring surface (sketch — finalized per phase as ADRs)

Tier 1 (declarative), reading like Vue's `<script setup>` but in Swift:

```swift
@Component struct PartsLive {
  // fetch-on-mount → three reactive cells; the view binds value/isLoading/error
  @Resource(get: "/api/parts", as: [Part].self) var parts
  // live channel → messages drive a re-render; status drives a badge
  @Channel("/ws/parts", as: PartEvent.self) var stream

  var body: some HTML {
    when(parts.isLoading) { Spinner() } else: {
      List(parts.value) { PartRow($0) }
    }
    .onChannel(stream) { /* declarative reducer: event → cell mutation */ }
  }
}
```

Tier 2 (escape hatch) authors a client `setup` module bound by name to a `[data-component]` root (today's
`mount("name", fn)`), now with the richer `ctx` of §4.3. The macro/type spellings (`@Resource`, `@Channel`,
`when/else`, `onChannel`) are **illustrative**; each becomes an ADR with the exact signature + wire encoding.

## 8. Security

- **Mediated network only.** Per the `Static` audit principle, the runtime never exposes a raw, unmediated
  sink. `ctx.fetch`/`ctx.ws` enforce **same-origin by default + an explicit cross-origin allowlist**; no
  arbitrary cross-origin reach.
- **CSRF** on every state-changing XHR (token via meta/header), coordinated with ADServe (RFC-0006 §4.5).
- **CORS** is an *allowlist*, never `*` with credentials; preflight enforced server-side (§5).
- **WebSocket** validates `Origin` at upgrade, authenticates the session, bounds message size + rate, and
  caps reconnect storms (backoff + jitter, §6).
- **No `eval`, no inline JS** (ADR-0006): Tier-1 sources are interpreted by the closed runtime; Tier-2
  modules are SRI-pinned + CSP-nonce'd, author-owned, out of core.
- **Data-leak boundary** (ADR-0005) holds: a component's fetched/subscribed state is owned by its island
  scope and serialized only within it — client-loaded data cannot leak across islands.
- **Response trust:** JSON is parsed (never `eval`'d); morph HTML stays server-authored + escaped at source.

## 9. Alternatives considered

- **Full client runtime (VDOM, Vue-faithful).** Rejected: abandons the fine-grained/resumable engine for a
  heavier diffing runtime + per-component bundles, a larger security surface, and a bigger budget — for no
  gain over fine-grained effects.
- **Declarative-only (Tier 1, no escape hatch).** Rejected per the chosen fork: too limited for genuinely
  bespoke widgets; Tier 2 is the pressure-relief valve that keeps Tier 1 small.
- **Status quo (Qwik-only, RFC-0006 stance).** Rejected: does not deliver component-owned XHR/WS reactivity.
- **Swift→WASM client.** Rejected (ADR-0006): the runtime stays a small generic JS interpreter.

## 10. Phasing

| Phase | Item | Needs ADServe? |
|---|---|---|
| 1 | ✅ `ctx.fetch` — failure-safe JSON XHR + AbortController + abort-on-teardown (`src/fetch.js`, iter #3). Cross-origin governed by server CORS, not a client block. ADServe **CORS already exists** (`Middleware.swift`) — wants only `App(cors:)` sugar | exists |
| 2 | `ws.js` managed WebSocket (reconnect/backoff/heartbeat/size-cap) + `ctx.ws`; ADServe typed **`Channel`** (origin/auth check, broadcast helper) over existing `WS` | **yes** (Channel) |
| 3 | Tier-1 **`Resource`** (fetch-on-trigger → value/isLoading/error cells) + new wire cell kind + the `.mount/.visible/.every/.on` triggers | partial |
| 4 | Tier-1 **`Channel`** Swift surface (messages/status/send cells) + declarative reducer (`onChannel`) → cell mutations | yes |
| 5 | Tier-2 reactive `ctx` (`ref/computed/effect/watch`, `onMounted/onUnmounted`) for bespoke widgets | no |
| 6 | **Proof:** spare-parts live updates — a part edit on one client pushes via `Channel` to others; the parts list becomes a `Resource`; remove a hand path | yes |

Phases 1–2 are the unblockers (the two missing network primitives + their ADServe counterparts) and deliver
"components issue XHR/WebSocket" directly. Phases 3–5 are the Vue-shaped authoring surface. Phase 6 is the
end-to-end demonstration in a real app.

## 11. Non-goals

No VDOM / virtual-list / client router in core (an opt-in module at most). No `eval`, no inline event
handlers (CSP). No arbitrary client templating language. No Swift→WASM (ADR-0006). The resumable engine,
islands, and hypermedia morph are **kept**, not replaced — this RFC adds a peer model, it does not remove the
existing one.

## 12. Open questions

- **Auth/session for component XHR/WS** — how the web-app session is presented to the API app (cookie scope
  across ports, or a token); the CORS credentials policy.
- **WS fan-out at scale** — in-process broadcast (PoC) vs an external bus; back-pressure when a slow client
  can't keep up.
- **Tier-1 expressiveness** — how far the declarative reducer (`onChannel`) goes before an author must drop
  to Tier 2; do we need a closed reducer verb set (like `Behavior`) or a small expression DSL.
- **SSR ↔ client ownership** — when a `Resource` both seeds server-side (first paint) and refetches client-
  side, who owns reconciliation; avoiding a flash of refetch.
- **Optimistic updates + rollback** for component XHR (snapshot/restore), reusing RFC-0006 §4.3.

## 13. References

- Vue 3 (reactivity, `<script setup>`, lifecycle), Solid (fine-grained, no VDOM), Datastar (SSE + signals),
  htmx / Hotwire-Turbo (hypermedia), Qwik (resumability). RFC-0003 (wire), RFC-0006 (client dynamic content),
  ADR-0005 (islands), ADR-0006 (runtime stance), ADR-0012 (ADServe). `ClientRuntime/src/{signals,action,
  mount,morph,wire}.js`; ADServe `ServerDSL.swift` (`WS`/`Stream`/JSON verbs).
