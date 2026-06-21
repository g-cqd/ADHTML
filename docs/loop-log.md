# Loop log — autonomous iteration across ADServe / ADHTML / spare-parts-app

A running record of the recurring `/loop` task (every 10 min). North stars: **(1)** ADServe is the most
performant server out there; **(2)** ADHTML is as mature as Vue; **(3)** spare-parts-app has implemented all
its ADRs + RFCs. Discipline: assess ×3 (pro / con / consolidate); pick the safest, most performant, most
SOTA option; minimal, secure, low-boilerplate; avoid recursion; commit **locally only, never push**; commit
**only my own files** (never sweep the user's in-progress work in the app/ADHTML trees).

---

## Iteration #1 — 2026-06-21

**Context inherited:** routing bug fixed (scope-root routes weren't inheriting their `Scope` path),
`Group`→`Scope` rename done, RFC-0008 (Vue-style client components) written, a `Static`→`/etc/passwd`
security probe audited.

**Assessment (×3):**
- *Pro* — the path-traversal audit surfaced a confirmed, dependency-free, testable hardening (reject
  NUL/C0/DEL control bytes in `decodeSegment`); and ADServe's working tree held only my own completed,
  green work, safe to preserve.
- *Con* — the deeper root-validation (audit P1) file-check only catches the *inert* probe and misses the
  actually-exploitable directory-misconfig; a CWD-escape check risks false positives on legit absolute
  deploy roots and needs a logging channel; pulling `Foundation` into the lean DSL is a cost.
- *Consolidate* — ship the **safe minimal** slice now (control-byte guard + a `Static(root:)` trust-boundary
  doc); **defer** root validation / allow-list policy to a *designed* follow-up (logged below).

**Done (ADServe, committed `6a8fe96`, local-only):**
- Reject NUL/C0/DEL control bytes in `PathTemplate.decodeSegment` — closes the `%00` open()-truncation
  near-miss platform-independently (audit P3). Black-box tests via `match`.
- `Static(root:)` documented as a trust boundary (every servable-extension file under `root` is public).
- Wrapped the exact-form verb overload signatures to satisfy `swift-format` LineLength (pre-existing debt the
  pre-commit hook surfaced).
- Carried in the same commit: the scope-path inheritance fix (`pathMatchesExact`) + `Group`→`Scope` rename.
- **260 ADServe tests / 64 suites green.**

**Done (ADHTML, local-only):** RFC-0008 + this log committed.

**Left untouched (correctly):** the app and ADHTML working trees carry the user's in-progress refactors
(`PersistenceADSQL`→`PersistenceADDB`, deleted `HTTPSupport.swift`, ADR/RFC/`ci.yml`/Benchmarks edits). Not
mine to commit. My app change (`Routes.swift` route-shape fixes + probe removal) stays in the working tree.

---

## Iteration #2 — 2026-06-21

**Trigger:** north star #1 (perf) + the "benchmark everything" mandate → establish a baseline. Recon found
ADServe **already has** an ordo-one suite (`Benchmarks/ADServeSuite`, malloc-tracked, gated `ADSERVE_DEV=1`)
covering `routing/*`. Sharper finding: **iteration #1's `pathMatchesExact` allocated up to 2 Strings per
exact-match comparison** (`String(requestPath) + "/"`) — a self-inflicted regression on the exact-match hot
path the `routing/exact hit` benchmark guards via `.mallocCountTotal`.

**Assessment (×3):**
- *Pro* — fixing it serves perf/memory-efficiency, self-corrects my own regression, reuses the existing
  harness (zero new infra).
- *Con* — the zero-alloc rewrite must be exactly equivalent across trailing-slash edges; the benchmark
  runner is finicky in this sandbox.
- *Consolidate* — rewrite allocation-free, prove equivalence with the 260 tests, document the harness +
  command; don't burn the fire fighting the sampling runner.

**Done (ADServe, committed `6f2b881`, local-only):**
- `pathMatchesExact` now normalizes **down** — trims one trailing slash via zero-copy `Substring` slicing
  (`dropLast`/`[...]`), preserving a lone `"/"`. **Allocation-free**, O(1) trim + O(path) compare, no
  recursion, empty-safe. Equivalent equality to the prior append-up version; **260 tests green**.

**Benchmark status:** harness is healthy — `swift package benchmark list` enumerates all benches
(`routing/exact hit`, `routing/param {1,2,3}-capture`, `catch-all`, `miss`, `405`, `mime/*`, `percent/*`,
`cookies/*`, `form/*`). The **sampling run emits no tables in this sandbox** (subprocess/TTY limitation,
independent of the jemalloc version-mismatch warning — `BENCHMARK_DISABLE_JEMALLOC=true` didn't help).
→ Capture numbers on a clean host/CI: `ADSERVE_DEV=1 swift package benchmark --filter routing`. The
allocation-freedom is meanwhile guaranteed *by construction* (no `String(_:)`/`+`, only slicing).

---

## Iteration #3 — 2026-06-21

**Trigger:** north star #2 (ADHTML as mature as Vue) → RFC-0008 **Phase 1** (component-issued XHR). Recon
corrected two RFC-0008 assumptions: ADServe **already ships a `CORS` middleware** (`Middleware.swift:111`),
and ClientRuntime has a real **TDD setup** (`bun test ./test`, happy-dom, `stubFetch`).

**Assessment (×3):**
- *Pro* — self-contained in `ClientRuntime/src`, TDD-able, the server CORS half already exists; direct
  "component issues XHR" progress.
- *Con* — must not regress the morph path or the ≤5 KiB budget; the security model needs a sane default
  (don't re-implement CORS client-side).
- *Consolidate* — add a small failure-safe JSON transport + `ctx.fetch`, abort-on-teardown, keep the morph
  path byte-identical, let the server's CORS govern cross-origin. TDD throughout.

**Done (ADHTML, committed `24cd1ed`, local-only):**
- `src/fetch.js` — `fetchJSON`: never-throws JSON transport (rejection/non-2xx/oversize/non-JSON → `null`),
  body-cap before parse, `AbortSignal`-aware. The JSON lane (no `ADH-Request` morph header).
- `src/mount.js` — `ctx` grows to `{ root, action, fetch }`; per-root `AbortController` aborted in
  `runCleanups`, so an unmounting component cancels in-flight `ctx.fetch` (Vue `onUnmounted` semantics).
- **75 ClientRuntime tests pass** (9 new); strict `tsc` typecheck clean; runtime **4.92 KiB gzip** (within 5).

**Corrected RFC-0008:** §5/§10 — ADServe CORS exists; Phase 1 reuses it (only ergonomic sugar may be wanted),
it is not a missing surface.

**Budget watch:** the runtime is at 4.92/5 KiB — Phase 2 (`ws.js`, `ctx.ws`) must adopt RFC-0008's opt-in
module split rather than grow the core.

---

## Iteration #4 — 2026-06-21

**Reassessment:** the backlog pointed at RFC-0008 Phase 2 (client `ws.js`), but two constraints redirected
me: the client runtime is at 4.92/5 KiB (Phase 2 needs a build-system code-split — too big for one safe
fire), and spare-parts is mid-refactor (audit unreliable; do not disturb). The **server** WebSocket half is
pure ADServe + clean for me — and the prism's "make safe" pillar surfaced a real gap: the WS upgrade
(`HTTPServerBootstrap.shouldUpgrade`) gated only on the path matching, **never on `Origin`** → Cross-Site
WebSocket Hijacking (CSWSH), which CORS does not cover (the upgrade isn't a CORS-gated request).

**Assessment (×3):**
- *Pro* — closes a real CSWSH vuln; secure-by-default; localized to `shouldUpgrade` (no routing-core
  threading); native clients (no `Origin`) keep working; the right sequencing — make the server WS safe
  before Phase-2 clients connect.
- *Con* — no per-route cross-origin allowlist yet (none in the AD-family need it); host:port compare has
  default-port edges.
- *Consolidate* — ship a pure, recursion-free, unit-testable same-origin gate + wire it into `shouldUpgrade`;
  log the allowlist follow-up.

**Done (ADServe, committed `004c2fc`, local-only):**
- `webSocketOriginAllowed(origin:host:)` (`WebSocket.swift`) — allow an absent `Origin` (non-browser, no
  ambient cookies) or a same-origin authority; reject cross-origin / `null` / scheme-less Origin or a missing
  `Host`. Pure (Foundation-free via stdlib `firstRange(of:)`), framework-agnostic, no recursion.
- Wired into `shouldUpgrade` — a cross-origin handshake no longer upgrades (falls to the route's 426).
- **264 ADServe tests green** (+4 CSWSH cases); the real WS echo upgrade still works; pre-commit hooks pass.

---

## Iteration #5 — 2026-06-21

**Trigger:** WS momentum (iter #4 made the server WS *safe*) → the highest-value Phase-2 piece is live
**broadcast/fan-out** — the Vue-defining "an edit on one client appears on the others". Swift `actor`s make
it data-race-free, so it's a safe single-fire slice.

**Assessment (×3):**
- *Pro* — highest north-star-#2 value (live updates); an `actor` gives free concurrency safety; concurrent +
  failure-isolated sends (no head-of-line blocking, a dropped peer can't break the rest); reusable primitive.
- *Con* — author owns the subscribe/unsubscribe lifecycle (auto-prune deferred); broadcast-without-a-typed-
  `Channel`-wrapper yet (the sugar layers on later).
- *Consolidate* — ship the `WebSocketHub` broadcast actor + tests; the `Channel` auto-subscribe DSL is next.

**Done (ADServe, committed `1b63648`, local-only):**
- `WebSocketHub` actor (`WebSocket.swift`) — `subscribe`/`unsubscribe`/`broadcast(_:to:)`/`subscriberCount`,
  topic-keyed. Sends run concurrently via `withTaskGroup` and are `try?`-isolated; the subscriber set is
  snapshotted before the fan-out (a concurrent (un)subscribe can't invalidate it); monotonic `&+` token.
- **268 ADServe tests green** (+4: topic isolation, unsubscribe-stops-delivery, failure isolation,
  unknown-topic no-op); pre-commit hooks pass.

**Phase-2 server foundation now complete:** CSWSH gate (iter #4) + `WebSocketHub` broadcast (iter #5). The
remaining server piece is the `Channel` DSL that *wraps* `WS` + the origin allowlist + auto-subscribe to a
hub; then the client `ws.js`/`ctx.ws`.

---

## Iteration #6 — 2026-06-21

**Trigger:** capstone the server WS story (iter #4 CSWSH gate + iter #5 `WebSocketHub`) — the hub's
doc-comment spelled out the subscribe / hold-open / unsubscribe boilerplate by hand; collapse it into a DSL
primitive (the prism's "reduce boilerplate / DSL").

**Assessment (×3):**
- *Pro* — turns 4 lines of lifecycle boilerplate into one; reuses `WebSocketHub` + the global CSWSH gate;
  pure ADServeDSL; completable + TDD-able; the natural server-WS capstone.
- *Con* — subscribe-only (typed-inbound + per-route allowlist deferred to stay minimal); the behavioural
  test needs determinism without sleeps.
- *Consolidate* — ship `Channel(_:on:topic:)` with **inline** unsubscribe-after-loop (deterministic, not a
  fire-and-forget `defer`); test via a controllable stream + a yield-loop.

**Done (ADServe, committed `317ea82`, local-only):**
- `Channel(_:on:topic:)` (`ServerDSL.swift`) — a `WS` endpoint that auto-subscribes the connection to a
  `WebSocketHub` topic on open and auto-unsubscribes on close/drop/quiesce; the server pushes via
  `hub.broadcast`. Cleanup is awaited inline (deterministic).
- **270 ADServe tests green** (+2: resolves-as-WS-route; auto-subscribe-while-open + unsubscribe-on-close,
  deterministic — no sleeps); pre-commit hooks pass.

**Server WebSocket story COMPLETE** (iters #4–6): CSWSH origin gate → `WebSocketHub` broadcast → `Channel`
auto-subscribe DSL. A live-update app is now ~3 lines server-side. The remaining RFC-0008 Phase-2 work is the
CLIENT (`ws.js` + `ctx.ws`, opt-in module) + the deferred sugar (typed inbound, per-route allowlist,
`App(cors:)`, hub auto-prune).

---

## Iteration #7 — 2026-06-21 (audit + native-leverage, not a feature)

**Reassessment:** the backlog's next item (client `ws.js`/`ctx.ws`) is gated on a build-system code-split —
`build.js` is a single `Bun.build` entrypoint with a hard 5 KiB gate and the core sits at 4.92 KiB (86 B
headroom), so `ws.js` needs a real second-bundle + lazy-`import()` + served-URL split (too build-risky for a
safe fire). And the loop had done 6 feature iterations while neglecting the prism's two most-repeated asks:
**"identify"** and **"leverage apple-docs"**. So this iteration diversifies to those.

**Done:**
- **Identify sweep of ADServe** (~6,700 hand-written lines, agent-assisted, every candidate grepped across
  Sources/Tests/Benchmarks). Result — a strong *integrity* signal: the codebase is very clean. The ONLY
  truly-dead internal symbol was the OpenAPI generator's `DocJSON.int` case (+ its serializer arm); the
  generator never emits a JSON integer. Removed it — behavior-preserving, exhaustiveness-safe (committed
  `739395d`; 62 DSL tests green). Everything else flagged (`MediaType` presets, `HTTPError` REST factories,
  the `UTType`/`Charset` init) is intentional public API. Verified false-positives: the deprecated `Group`
  alias is tested; `percentDecodeToken`'s `i+2` bound is correct; `SSELimiter`/`ConnectionLimiter` differ by
  design; streaming routes' dropped route-middleware is documented.
- **Native-leverage check (apple-docs)** on `WebSocketHub`: the only broadcast-to-subscribers primitives are
  **Combine** `PassthroughSubject`/`Publishers.Multicast` (Apple-only → unusable in a Linux server) and
  `swift-async-algorithms` `AsyncChannel` (a single back-pressured handoff, not topic-keyed fan-out). →
  the hand-rolled actor `WebSocketHub` is the correct cross-platform design; **no native-leverage gap.**

**Assessment (×3):** *Pro* — honors the under-served prism pillars; the sweep doubles as an integrity audit;
the one fix is provably safe. *Con* — small code delta (a clean codebase yields little to cut). *Consolidate*
— ship the dead-case removal + record the audit + native-leverage conclusions as durable findings.

---

## Iteration #8 — 2026-06-21

**Trigger:** client `ws.js` is still gated on the build-system code-split (its own ADR-sized change), and
iter #7 was an audit — swing back to feature completion. Finish the `Channel` DSL with its **typed-inbound
overload** (predictable, completable, reduces decode boilerplate, leverages the in-house ADJSON codec).

**Assessment (×3):**
- *Pro* — completes Channel (bidirectional); failure-safe decode; reuses ADJSON (no new dep beyond an import);
  dedups the lifecycle; TDD-able deterministically.
- *Con* — inbound (client→server) is the lower-frequency direction vs broadcast; WS-adjacent (4th WS-area
  fire).
- *Consolidate* — ship the overload + a shared `serveSubscribed` helper so the two forms don't duplicate the
  subscribe/unsubscribe lifecycle.

**Done (ADServe, committed `40cb976`, local-only):**
- `Channel(_:on:topic:receiving:_:)` — decodes inbound text frames as `Inbound` (JSON via ADJSON), delivers
  them with the connection. Failure-safe: a non-text/undecodable frame is `try?`-skipped, never thrown.
- Refactor: both overloads route through a private `serveSubscribed(_:on:topic:_:)` (subscribe → serve →
  awaited unsubscribe) — the lifecycle lives in one place (the prism's de-dup).
- **271 ADServe tests green** (+1: decodes two valid frames in order, skips garbage + a binary frame);
  pre-commit hooks pass (caught + fixed an `OrderedImports` slip).

**`Channel` DSL is now complete** — subscribe-only (server push) + bidirectional typed. The WebSocket server
story (iters #4–6, #8) is feature-complete; only the client (`ws.js`/`ctx.ws`, code-split-gated) remains.

---

## Carry-forward backlog (the "identify" pillar — fuel for later iterations)

**ADServe — security / robustness**
- *(P1)* Build-time `root` validation for `Static`. Design needed: a file-vs-dir `precondition` catches only
  the inert probe; the real win is flagging a `root` that escapes the project CWD (catches `/etc/ssl`, `..`
  climbs) — but must be a *warning*, not a trap (legit absolute deploy roots exist), and needs a stderr
  channel without dragging `Foundation` into the DSL. Consider POSIX `stat` + `fputs`.
- *(P2)* Tighten the default servable extension set — drop `.txt`/`.json`/`.map`/`.xml` from the *default*
  (they're what leak `credentials.json` / sourcemaps under a misconfigured dir root). **Breaking** → needs an
  explicit decision + an opt-in.
- *(P4)* `O_NOFOLLOW` on the static `open()` (residual symlink TOCTOU). *(P5)* assert `root` absolute in
  `isInsideRoot` once P1 canonicalizes.
- Add `PathTraversalTests` cases for the directory-root exposure + NUL extension confusion (audit gap).

**ADServe — performance (north star #1)**
- Micro-bench harness CONFIRMED healthy (ordo-one `Benchmarks/ADServeSuite`, malloc-tracked; `list` works).
  The sampling run is blocked in this sandbox (subprocess/TTY) — capture the `routing/*`, `percent/*`,
  `mime/*` baseline on CI / a clean host and commit it as the tracked reference. A live-load test (req/s +
  p99) also wants a load tool (none of wrk/bombardier/hey/oha installed here).
- `pathMatchesExact` made allocation-free (iter #2). Next: scan other DSL hot paths for incidental
  allocations the malloc gate would catch.

**ADHTML — Vue maturity (north star #2)**
- RFC-0008 Phase 1 `ctx.fetch` DONE (iter #3). **Server WS COMPLETE** (iters #4–6, #8): CSWSH gate +
  `WebSocketHub` + `Channel` (subscribe-only + typed-inbound). Next CLIENT: `ws.js` + `ctx.ws` as an OPT-IN
  module — **gated on a build-system code-split** (core at 4.92/5 KiB): `build.js` → a second `adh-ws` bundle
  the core lazy-loads via `import(new URL("./adh-ws.js", import.meta.url))`, per-chunk budget, the test
  resolving `./ws` from source. That split is the one structural prerequisite left (its own ADR). Smaller
  deferred sugar: per-route cross-origin WS allowlist; `App(cors:)`; hub auto-prune on send failure.
- Tier-1 declarative `@Resource`/`@Channel` Swift surface (RFC-0008 §4.2/§7) — the no-JS path — comes after
  the Tier-2 primitives (`ctx.fetch` done, `ctx.ws` next) land + prove out.
- Boilerplate: the 7 verb-overload pairs in `ServerDSL.swift` are near-identical — a candidate for a macro
  (the prism's "macros where relevant" / "reduce boilerplate"). Assess before doing (macros add build cost).

**spare-parts-app (north star #3)**
- Audit which ADRs/RFCs are implemented vs pending (the app's `docs/adr` + `docs/rfcs`), turning #3 into a
  tracked checklist. Blocked on the user's in-flight `PersistenceADDB` refactor settling — do not disturb.

**CI / buildtime / runtime**
- ADServe pre-commit runs SwiftLint + swift-format strict (good). Confirm the same gate exists in ADHTML +
  the app, and that CI runs the full suites with the `AD*_PATH` env. Consider a `--warnings-as-errors` gate.
