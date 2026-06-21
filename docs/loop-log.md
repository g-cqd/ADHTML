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

## Iteration #9 — 2026-06-21 (diversify to ADHTML; audit + cleanup)

**Reassessment:** 8 iterations in, 7 had touched ADServe — the loop neglected ADHTML (1×) and spare-parts
(0×, correctly — mid-refactor). The client `ws.js` is still code-split-gated (its browser lazy-load is
unverifiable in this sandbox). So diversify: an identify sweep of ADHTML's Swift sources (agent-assisted,
scoped away from the JS runtime + user WIP).

**Done (ADHTML, committed `04a0efe`, local-only):**
- Sweep result — like ADServe (iter #7), ADHTML is *very clean*: dense docs, parity tests for every wire
  surface, no dead types. The ONE truly-dead item: two `ADHTMLDiagnostic` cases (`stateRequiresStoredVar`,
  `stateNeedsType`) left behind when `@State` moved from a macro to a runtime property wrapper (an ADR-0008
  leftover) — no `StateMacro` exists, so nothing emits them. Removed the cases + both switch arms each
  (balanced, exhaustive switches preserved). **253 tests green**, macro plugin builds.
- The two duplications the sweep found (a `lower` render helper; an `accessModifier` macro helper) — agent
  and I both judged **skip**: factoring touches the render/macro paths for negligible gain.

**Assessment (×3):** *Pro* — diversifies (loop coherence), honors the "identify" pillar on a fresh codebase,
excises an ADR-0008 leftover. *Con* — small delta (a clean codebase yields little). *Consolidate* — ship the
one safe removal + record the integrity signal.

**Integrity signal (both repos now swept):** ADServe (iter #7) and ADHTML (iter #9) are both well-maintained —
the only dead code across ~12k lines was ~8 lines total (an OpenAPI enum case + two macro diagnostics). The
loop's value is now feature/hardening work, not cleanup.

---

## Iteration #10 — 2026-06-21

**Trigger:** iter #9's own recommendation — close the `WebSocketHub` reliability gap (a half-open/dropped peer
whose inbound stream hasn't ended stays subscribed forever, drawing a doomed send on every broadcast).

**Assessment (×3):**
- *Pro* — closes a real memory/CPU leak; failure-safe + memory-safe + reliability (prism core); self-contained;
  verifiable with the existing mocks; concurrency-safe via actor isolation + monotonic tokens.
- *Con* — `broadcast` gains a token-collect + prune step (slightly more than the prior 5-liner).
- *Consolidate* — collect the tokens whose send threw, prune them after the fan-out; the snapshot + monotonic
  tokens make the post-await prune race-free.

**Done (ADServe, committed `3164ea5`, local-only):**
- `WebSocketHub.broadcast` now PRUNES a subscriber whose `sendText` throws — reclaiming a dead peer instead
  of re-attempting a doomed send forever. Still failure-isolated (a throwing send never blocks the others).
  Race-free: pruning only the snapshot's failed (old) tokens can't drop a subscriber that (re)joined during
  the await.
- **272 ADServe tests green** (+1: a failing peer is pruned on its first broadcast, not re-attempted later);
  pre-commit hooks pass.

**`WebSocketHub` is now reliability-complete:** concurrency-safe (actor) + failure-isolated + auto-pruning.
With the CSWSH gate + Channel (subscribe-only + typed-inbound), the whole WebSocket *server* is hardened.

---

## Iteration #11 — 2026-06-21 (perf recon → integrity fix)

**Trigger:** north star #1 (perf), the most under-served goal. Targeted a *specific* classic hot-spot rather
than a blind hunt: the per-response `Date` header.

**Recon result (no safe win to force):** ADServe's response path is already excellent — there is **no
per-response `Date` header by design** (the engine is proxy-fronted; the "fetch + Caddy" note at
`HTTPServerRespond.swift:494` confirms Caddy adds it), `HTTPDate.format` is used only for static
`Last-Modified` (not a hot path), and `commonHeaders` is a cached `envelope` + minimal per-request work. The
two clean sweeps (iters #7, #9) already signaled this. The remaining code targets are each either ADR-sized
(`ws.js` code-split — browser lazy-load unverifiable here), engine-threading-heavy (the WS cross-origin
allowlist, ~7 touch points through the routing/bootstrap core), or marginal-with-awkward-tests (`App(cors:)`
sugar — middleware is engine-applied, not visible to the route-table unit harness). Forcing one of those is
not the "safest, most value" move.

**Done (ADHTML, integrity fix — `docs/rfcs/0008-...md`):** RFC-0008 was written design-first ("awaiting
approval before implementation"), but iters #4–6/#8/#10 *built* the Phase-2 server — the canonical spec now
contradicted reality. Reconciled it: updated the **Status**, the **§5 WebSocket-channel** section (now
"BUILT & hardened" with the as-built `WebSocketHub`/`Channel`/`webSocketOriginAllowed` API), and the **§10
phasing table** (Phase 2 server ✅, client pending). The prism's coherency/consistency/integrity +
"document everything".

**Assessment (×3):** *Pro* — keeps the canonical design doc honest; safe (doc-only); the recon itself is a
useful negative result (perf is already optimal). *Con* — a lighter, no-new-code fire. *Consolidate* — record
the perf finding + reconcile the spec; do not manufacture a marginal code change to look busy.

**Honest state of the loop:** after 11 iterations the obvious high-value *safe* code targets are done. The
genuine remaining work is (a) the `ws.js` client code-split — ADR-sized, partially unverifiable in this
sandbox, deserves a deliberate session; (b) spare-parts' ADR/RFC implementation — blocked on the user's
in-flight `PersistenceADDB` refactor; (c) the Tier-1 declarative `@Resource`/`@Channel` Swift surface — a
macro + wire-format effort. The next fires should pick one of these deliberately rather than chase diminishing
small wins.

---

## Iteration #12 — 2026-06-21

**Trigger:** the one genuine, safe, *completable* win left (the meaty options — `ws.js` code-split, Tier-1
`@Resource` macro — don't fit a safe single fire; spare-parts is blocked). `App(cors:)` makes the cross-port
`ctx.fetch` pattern (web app → JSON API on another port, the spare-parts two-port shape) discoverable + one
line, instead of a dev needing to know to hand-wire `middleware: [CORS(...)]`.

**Assessment (×3):** *Pro* — real ergonomic + discoverability win for the architecture the loop has been
building toward (`ctx.fetch` + cross-port CORS); additive + backward-compatible; verifiable structurally
(`CompiledRoute.middleware` is `public`). *Con* — modest in size. *Consolidate* — add `cors:` (prepended
OUTERMOST so it owns the preflight), test it wires CORS first + stays opt-in.

**Done (ADServe, committed `630f54f`, local-only):**
- `App(cors: CORS? = nil, …)` installs the `CORS` middleware outermost in one line — exactly
  `[CORS(…)] + middleware`. Backward-compatible (default nil; the `middleware:` array still works).
- **273 ADServe tests green** (+1: CORS wired first with the right origin, and strictly opt-in); hooks pass.
- RFC-0008 §5 + phasing table updated (CORS sugar now built, not just wanted).

**Backlog now:** the remaining items are all deliberate efforts, not loop-sized — `ws.js` client code-split
(ADR, partly unverifiable here), the Tier-1 `@Resource`/`@Channel` macro+wire surface, and the per-route WS
cross-origin allowlist (the one engine-threading item; ~7 touch points). The next fire should commit to one
of these as a focused task.

---

## Iteration #13 — 2026-06-21 (grounded finding: ADHTML is prototype-parity-complete)

**Trigger:** re-evaluate the stale "spare-parts blocked" assumption + advance north star #3. The app is STILL
mid-`PersistenceADDB`-refactor (heavy uncommitted WIP) so its code stays off-limits — but it carries new
untracked **RFCs 0019–0022**, the app's *requirements on the framework*. RFC-0021 specifies 9 ADHTML
primitives (P1–P9) for exact prototype parity and assumes "+2–3 KiB" of runtime (≈7 KiB), which seemed to
conflict with ADHTML's 5 KiB ADR-0006 budget.

**Finding (the hypothesis was WRONG — verified, grounded):** ADHTML *already implements the entire P1–P9
vocabulary, in the 4.92 KiB budget*. Verified by markers + types + tests:
- P1 `.model` / P2 `.classToggle` (`data-adh-class`) / P6 `.show`+`When` (`data-adh-show`/`-if`) / P7 boost
  (`Boost.swift`, `Link`) / P8 store (`AppStore.swift`) — present.
- P3 client list (`data-adh-each`, `ForEach.swift`, `ClientListTests`); P4 keyboard/behavior vocab
  (`listMove`/`setFromValue`/`removeLast`/`keydown`/`data-adh-keys`, `EventVocabTests`); P5 extended
  expressions (`.filter`/`highlight`/`contains`); P9 `TokenField.swift` — all present + parity-tested.
- The closed-vocabulary + build-time token-mangling fit all nine in ~5 KiB; **the budget "conflict" doesn't
  exist.**

**Verification (all green across the 12 prior iterations):** ADHTML Swift **253**, ClientRuntime JS **75**,
ADServe **273**.

**Revised north-star-#2 assessment:** ADHTML's client is *prototype-parity-complete* (RFC-0021 P1–P9, tested,
in budget) AND now carries the RFC-0008 XHR/WS layer (server done iters #4–6/#8/#10/#12; `ctx.fetch` iter #3).
"As mature as Vue" is substantially met at the framework level. The only genuinely-missing client piece is
the RFC-0008 WebSocket CLIENT (`ws.js`/`ctx.ws`), still code-split-gated.

**Assessment (×3):** *Pro* — corrects a wrong mental model with grounded evidence; records that #2 is largely
achieved; pure verification (no risk). *Con* — a finding, not new code. *Consolidate* — record it honestly;
do not invent a change to look busy when the framework already has the capability.

---

## Iteration #14 — 2026-06-21 (grounded finding: the framework goals are substantially met)

**Trigger:** the prism's least-served dimension — "suggest improvement: CI" — then "document everything".

**Findings (both already done — verified):**
- **ADServe CI is excellent + complete.** `.github/workflows/ci.yml`: a reusable `quality` job (format + lint +
  test under **ASan + TSan** + coverage), a `mime-codegen-drift` guard, a `fuzz` job (the untrusted-byte
  parsers), and a `benchmark` job. The one open item — `benchmark` is `continue-on-error` pending a committed
  baseline — is blocked by the SAME sandbox limit as iter #2 (the ordo-one sampling run can't generate a
  baseline here). No safe CI gap to fill.
- **ADHTML already has full user docs.** Two DocC catalogs, **947 lines across 9 articles** (`GettingStarted`,
  `InteractiveComponents`, `DerivedState`, `MarkdownInBuilder`, `ComponentScopedAssets`, `Reactivity`,
  `RenderingModel` + both landings) — substantive, matching the original plan. Not a stub; not a gap.

**Meta-finding (the honest one):** this is the THIRD consecutive iteration where my hypothesized gap was
already filled — iter #12 ≈ (CORS existed), iter #13 (P1–P9 primitives exist), iter #14 (DocC exists). The
repeated pattern is itself the conclusion: **ADHTML + ADServe substantially meet the framework north stars.**
- **#1 (most performant server):** ADServe is fast + allocation-tracked + ASan/TSan-clean + fuzzed + cleanly
  swept. Optimal within what's verifiable here.
- **#2 (ADHTML as mature as Vue):** parity-primitive vocabulary (P1–P9), the RFC-0008 XHR/WS server,
  `ctx.fetch`, full DocC docs, 253 + 75 tests. Substantially met. Only the WS *client* (`ws.js`/`ctx.ws`)
  remains — blocked on a budget decision (the stub exceeds the 86 B core headroom).
- **#3 (spare-parts ADRs/RFCs):** the app's framework requirements (RFCs 0019–0022) are met; the app's own
  code is blocked on the in-flight `PersistenceADDB` refactor.

**Assessment (×3):** *Pro* — records grounded truth; avoids manufacturing churn on a mature codebase. *Con* —
no new code (correctly — there's nothing safe + unfilled to add). *Consolidate* — report completion honestly;
the next real moves (`ws.js` budget call, spare-parts settling) are **deliberate, user-involved** decisions,
not autonomous loop fires. Continuing to force micro-changes past here trades integrity for motion.

---

## Iteration #15 — 2026-06-21 (the deferred WS client — unblocked + shipped)

**Trigger:** stop deferring. The user empowered me to "pick the safest, most SOTA way" and not ask, so rather
than report "blocked" a third time, I MEASURED the real unknown: does a `ctx.ws` lazy-load stub fit the 86 B
core headroom? It does — the core grew only **43 B** (5034 → 5077, still within 5 KiB), because the
dynamic-URL `import()` minifies far smaller than I'd estimated and Bun leaves it un-bundled.

**Done (ADHTML, committed `a7a4c91`, local-only) — RFC-0008 Phase-2 CLIENT, the last missing piece:**
- `src/ws.js` — `open(url, signal, {onMessage, onStatus}) -> { send, close }`: a failure-safe managed
  WebSocket (never throws — bad URL → inert handle, oversized frame dropped, non-JSON delivered raw, throwing
  handler can't break the socket, send-after-close is a no-op), JSON in/out, closed on the component's
  `AbortSignal`. Shipped as an **opt-in code-split bundle** `adh-ws.min.js` (**369 B gzip**, its own 2 KiB
  gate) that the core lazy-loads only when a widget calls `ctx.ws` — zero bytes for pages that don't.
- `src/mount.js` — `ctx` grows `{ root, action, fetch }` → `+ ws`. `build.js` — a second `Bun.build` emits
  the opt-in bundle, core build untouched.
- **81 ClientRuntime tests** (+6: status, JSON/raw/oversized inbound, gated send, abort-close, failure-safe,
  inert-handle); strict `tsc` clean; **core 5077 B + adh-ws 369 B, both in budget.** RFC-0008 Status +
  phasing table updated (Phase 2 ✅ end-to-end).

**Assessment (×3):** *Pro* — closes the one genuine remaining client gap; the code-split is the minimal/SOTA
resolution (core stays small, WS opt-in); fully unit-tested + budget-verified. *Con* — the browser lazy-load
itself (a standard ESM dynamic import) isn't exercised by the unit suite — a real-env e2e is the final
confidence step; reconnect/backoff is a v2. *Consolidate* — ship the verified core + module; document the one
unverified-here edge honestly.

**Lesson:** twice this session (#13 P1–P9, #14 DocC) my "gap" was already filled; here the "blocker" dissolved
on measurement. Measure before deferring.

---

## Iteration #16 — 2026-06-21 (ws.js v2: auto-reconnect)

**Trigger:** apply #15's lesson + harden what I shipped. The v1 WS client (#15) had no reconnect — fragile
for "live updates" (one blip drops the socket forever). Add reconnect (the natural v2), in the same opt-in
module, deterministically testable.

**Done (ADHTML, committed `a4b92ef`, local-only):**
- `ws.js` v2 — an UNEXPECTED drop reconnects with capped exponential backoff (250 ms → 30 s ceiling) +
  50–100% jitter; a clean open resets the backoff. A deliberate `close()`/abort sets a `stopped` flag that
  suppresses reconnect; a malformed-URL construction throw gives up (no retry storm). `setTimeout`-driven —
  no recursion.
- **The code-split pays off:** all of it lands in `adh-ws.min.js` (369 → 464 B gzip, still < 2 KiB) — the
  core runtime is **byte-for-byte unchanged** (5077 B). Robustness for free, core-wise.
- **84 ClientRuntime tests** (+3, deterministic via a captured-`setTimeout` mock — no real waiting):
  reconnect-on-drop with a bounded delay, no-reconnect-on-deliberate-close, backoff-grows. Strict `tsc` clean.

**Assessment (×3):** *Pro* — production-robust WS client; zero core cost (opt-in); reconnect's footguns
(retry-on-deliberate-close, retry-storm-on-bad-URL) are explicitly guarded + tested. *Con* — heartbeat/ping
(detecting a half-open socket faster) is still a v3. *Consolidate* — ship reconnect; document heartbeat as
the next robustness step.

**Status:** RFC-0008 Phase 2 is now not just complete but *hardened* end-to-end (server: CSWSH + hub +
auto-prune + Channel; client: ctx.ws + reconnect). The remaining RFC-0008 work is Phase 3 — the Tier-1
declarative `@Resource`/`@Channel` "no-manual-JS" Swift surface.

---

## Iteration #17 — 2026-06-21 (grounded finding: RFC-0008 Phase 3 is superseded)

**Trigger:** apply #15's measure-don't-defer to the next RFC-0008 feature — Phase 3, the Tier-1 declarative
`@Resource` ("no-JS" client fetch-on-load → signal). To scope it I read the runtime's hydrate + cell model.

**Finding (fourth maturity surprise this session):** the runtime ALREADY has declarative live updates.
`connect(url, state, doc)` (`runtime.js:329`) subscribes an island carrying `data-adh-connect` to an **SSE**
stream and applies `patch` (set cells, with integer+bounds guards) / `morph` (swap an island by id, `CSS.escape`d)
frames — no manual JS. ADServe ships SSE. So the live-data space is comprehensively covered:
- **SSR** — initial data (the server already rendered it; the SSR-first model).
- **declarative SSE `connect`** — continuous server-push (`patch`/`morph`), zero JS.
- **`ctx.fetch` / `ctx.ws`** — imperative client fetch / bidirectional socket (iters #3, #15–16).

→ Phase 3's `@Resource` (a declarative *client* fetch-on-load) is the SPA pattern an SSR-first framework
rarely needs; it overlaps the existing mechanisms. **Not a gap — a spec to reconcile.** Updated RFC-0008
(Status + phasing row 3 → "superseded").

**Verification:** ClientRuntime **84** tests green (the WS client + the rest).

**Assessment (×3):** *Pro* — corrects the design doc with grounded evidence; avoids building a redundant
feature; SSR-first integrity. *Con* — a finding, not new code (correct — the capability exists). *Consolidate*
— record + reconcile; don't manufacture overlap.

**The pattern is now unmistakable** (iters #12–14, #17): four times a hypothesized "gap" was already filled
(CORS, P1–P9, DocC, declarative-live-updates). ADHTML + ADServe are comprehensively mature. My session's one
genuinely-new, non-redundant capability — **WebSocket support (server stack + `ctx.ws`)**, the user's explicit
ask — is built + hardened. RFC-0008 is, in substance, COMPLETE.

---

## Iteration #18 — 2026-06-21 (north star #3: a real spare-parts bug, fixed)

**Trigger:** re-measure the stale "spare-parts blocked" assumption (#15's lesson). It paid off: despite 26
uncommitted changes mid-`PersistenceADDB` refactor, the app now **builds** (10.9 s) and its tests run — so #3
is reachable read-only.

**Found (a genuine bug, via the app's own failing test):** `ViewKitTests → actionWiring` failed — the
rendered list page lacked `action="/parts/1/delete"`. Root cause: `PartsListView.swift:146` emitted the
row-delete form as `method="delete"` `action="/parts/1"`. But **HTML forms support only GET/POST** —
`method="delete"` silently degrades to GET — and the URL didn't match the route I set in iter #1
(`POST /parts/{id}/delete`). So the no-JS row delete was broken. (The token-field deletes already used
`POST …/delete` correctly; only the row delete was left inconsistent by the refactor.)

**Done (spare-parts, working tree only — NOT committed):** one-line fix —
`method="delete" action="/parts/1"` → `method="post" action="/parts/1/delete"`, matching the route + valid
HTML + the test. **Now 18/18 app tests pass** (was 17/18). Verified there is no other `method="delete"` in
ViewKit.

**Why not committed:** spare-parts is the user's active WIP (mid-refactor, untracked `ViewKit/`). Committing
one file would fragment the refactor — the fix lives in the working tree for the user to land with their
refactor commit (the same discipline as iter #1's `Routes.swift`).

**Assessment (×3):** *Pro* — advances the one untouched north star with a real, test-confirmed bug fix; safe
(obviously-correct 1-liner, matches the established route + valid HTML). *Con* — left uncommitted (correct —
respects the user's in-flight refactor). *Consolidate* — fix + verify + document; don't commit into the
user's WIP.

**#15's lesson, four-for-four:** the WS "budget blocker" (#15), the reconnect "untestable timing" (#16), and
now the spare-parts "blocked" assumption all dissolved on measurement. Re-measure before deferring.

---

## Iteration #19 — 2026-06-21 (north star #3: live end-to-end verification)

**Trigger:** re-measure once more (#15's lesson). The app builds + unit-tests pass (#18) — but does the
*refactored* app actually RUN end-to-end? No live integration test exists (`runner.swift` composes routes
without HTTP; ADServe's serving is tested separately), so this is the one un-done verification — and the
session opened with "investigate the running server."

**Done (read-only live smoke test — throwaway DB, unused ports, server stopped + cleaned up after):**
- `GET /parts` (web) → **200**, a full 112 KB SSR document: the runtime `<script>` (×2 markers), inline
  `adh-state` (×3), the create form (`action="/parts"`), and **21 `tokenfield` comboboxes** over the seeded
  data — the SSR shell + interactive islands render correctly.
- `GET /api/parts` (api) → JSON of the seeded parts (`{"id":2,"ref":"BRG-6204","name":"Ball bearing …",…}`).
- `POST /api/parts` (a LIVE mutation) → created **part id 11 "Live Smoke Test"** (generated ref `SP-YKAHX`,
  defaulted status, empty relations) — write path + ADDB persistence work.

→ **The refactored app (post-`PersistenceADDB`) runs correctly end-to-end** — NIO serve + ADDB + ADHTML SSR +
JSON API + mutations. North star #3 is now FUNCTIONALLY validated at runtime, not just by unit tests
(18/18) + the iter-#18 bug fix.

**Assessment (×3):** *Pro* — verifies the integration layer the unit tests can't (the live composition root +
serving); confirms the refactor is sound; safe (read-only run, temp DB, killed + cleaned up). *Con* — a
verification, not new code. *Consolidate* — run it, record the evidence, leave nothing behind.

**#3 status:** spare-parts builds + 18/18 unit tests + a live end-to-end smoke (web SSR + API + mutation). Its
testable + runnable scope is validated; any remaining untested ADR/RFC requirements are unblocked once the
user lands the in-flight `PersistenceADDB` refactor.

---

## Iteration #20 — 2026-06-21 (north star #3: web mutations + the iter-#18 fix, proven live)

**Trigger:** #19 validated reads + one API mutation, but not the WEB form mutations (the no-JS path) — and,
critically, not the **iter-#18 delete fix** at runtime. Re-measure the mutation paths.

**Done (read-only live smoke — throwaway DB, unused ports, stopped + cleaned up):** drove the no-JS form
flow, checking state via the API (deltas, since the count includes nested relation ids):
- `POST /parts` (web create form) → **303 → `/parts/11`**; count **+1** — create works.
- `POST /parts/11/delete` (**THE ITER-#18 FIX**) → **303 → `/parts`**; count **−1, back to baseline** — the
  fixed `method="post" action="…/delete"` form **actually deletes the part end-to-end.** The bug I fixed by
  inspection (#18) is now proven by execution.
- `GET /parts/1` (detail) → **200**. `POST /parts/1/manufacturers` (web token add) → **303 → `/parts/1`**.

→ The whole no-JS web mutation surface (create / delete / token add / detail) works live, and the iter-#18
correctness fix is confirmed under real execution — not just by the unit test.

**Assessment (×3):** *Pro* — closes the verification loop on #18 with executable proof; validates the no-JS
PRG (post-redirect-get) flow the app's progressive-enhancement design depends on; safe (read-only, temp DB,
cleaned up). *Con* — verification, not new code. *Consolidate* — exercise + record; leave nothing running.

**#3 is now comprehensively validated:** builds + 18/18 unit tests + live SSR reads + live API + **live web
mutations incl. the proven delete fix**. The app's implemented scope is sound end-to-end; any untested
ADR/RFC requirements remain unblocked pending the user's `PersistenceADDB` refactor landing.

---

## Iteration #21 — 2026-06-21 (a deploy gap my own code-split created — found + fixed + the morph path proven)

**Trigger:** re-measure the INTERACTIVE path (not just the no-JS PRG of #20): does the runtime asset serve,
and does the RFC-0019 morph-fragment contract work?

**Found (a real gap my iter-#15 code-split introduced):** the app's `SyncRuntime` SwiftPM plugin
(`swift package sync-runtime`) copies ADHTML's `adh-runtime.min.js` into `Public/` — but **not the
`adh-ws.min.js` opt-in bundle the code-split added.** Any app using `ctx.ws` would lazy-load a 404. My own
work left the deploy incomplete.

**Done (spare-parts working tree — NOT committed, user WIP):**
- `Plugins/SyncRuntime/SyncRuntime.swift` — extracted a `sync(_:into:required:fm:)` helper (de-dup) and now
  copies BOTH the required core `adh-runtime.min.js` AND the optional `adh-ws.min.js` (copy-if-present,
  forward-compatible). Ran `sync-runtime` → both land in `Public/` (13197 B + 714 B).
- **Validated live:** `/assets/adh-runtime.min.js`, `/assets/adh-ws.min.js`, `/assets/app.css` all **200**;
  `POST …/manufacturers` with `ADH-Request: 1` → **200 `text/html`** chip fragment (`token-name`/`token-x`,
  the new value), without it → **303** PRG. The RFC-0019 interactive ⇄ no-JS dual-path works end-to-end.

**Assessment (×3):** *Pro* — found + closed a deploy gap I created (the responsible finish of the code-split);
validated the app's interactive enhancement (the morph the runtime drives); safe (the plugin change is
obviously-correct + run-proven). *Con* — left in the user's WIP (correct). *Consolidate* — complete the
code-split's deploy, validate, document.

**#3 fully exercised:** build + 18/18 unit + live SSR + API + web mutations (incl. the proven delete fix) +
static assets + the interactive morph fragment. The app's no-JS AND runtime-enhanced paths are both proven.
**Seventh re-measure to pay off** (#15→#21): the "interactive path" check surfaced a concrete deploy gap.

---

## Iteration #22 — 2026-06-21 (the browser e2e — the deepest layer, green + benchmarked)

**Trigger:** re-measure the one layer I'd assumed unverifiable all session — the runtime's actual DOM behavior
in a real browser (the unit tests note the glue is "browser-validated, Playwright e2e").

**Found:** Playwright **is** set up and Chromium **is** installed — the layer is runnable here. (Eighth time a
"can't verify / blocked" assumption dissolved on measurement.)

**Done — ran the full browser e2e (Chromium, headless): 7/7 PASS in 2.0 s.**
- Hydration (load islands + lazy `visible` via IntersectionObserver); delegated click → bound node.
- Actions: live-search fetches a fragment + morphs the target; `Island(connect:)` subscribes to **SSE** and
  morphs on a pushed frame (the declarative live-update path from #17 — now browser-proven).
- Morph + rewire: a morphed-in editable field hydrates and stays two-way live across a search-morph.
- v2 authoring: `$state` + `@Bound` hydrate, bind, recompute derived state IN-BROWSER (no round-trip).
- **Benchmark (finally a real number — the loop's "benchmark everything"):** real-browser hydrate of 500
  islands in **3.2 ms (6.4 µs/island)**; 2000 delegated click round-trips in **8.4 ms (4.20 µs/click)** —
  native-DOM fast.

**This validates north star #2 at the deepest level:** the ADHTML runtime hydrates, binds, morphs, fetches,
SSE-streams, and recomputes derived state correctly + fast in a real browser. Combined with the unit (84) +
live-server (#19–21) layers, the runtime is proven end-to-end.

**Assessment (×3):** *Pro* — the deepest validation (real browser); produces the perf numbers the loop asked
for that the server benchmark couldn't (sandbox-blocked, #2); confirms hydration/morph/SSE/v2 all work. *Con*
— verification, not new code. *Consolidate* — run it, record the green + the numbers.

---

## Iteration #23 — 2026-06-21 (the last browser-only gap: `ctx.ws` lazy-load + WS round-trip, e2e-proven)

**Trigger:** #22 proved the runtime in a real browser — but its e2e covered hydration/morph/SSE/v2, **not**
`ctx.ws`. The WS client (#15–16) is the one path the unit suite *structurally cannot* reach: it lazy-loads the
opt-in `adh-ws.min.js` via `import(new URL("./adh-ws.min.js", import.meta.url).href)`, which only resolves +
fetches + executes in a real module loader. #15 itself flagged "its browser lazy-load isn't verifiable in this
sandbox" — re-measure that assumption, the throughline of this whole loop.

**Found:** it *is* verifiable — Playwright + Chromium run here (#22). So I built the missing fixture: a
`data-0="WsWidget"` widget whose `ctx.ws` opens a socket against a Bun `/ws-echo` endpoint that pushes one
frame on open + echoes a sent frame. Two real findings surfaced while wiring it:
- A page with **no `adh-state` script** makes `hydrate()` return early (runtime.js:278) → `mountAll` never
  runs → `activeDoc` stays unset → even a late `ADH.mount` can't mount. The fixture needs an (empty) state
  block. (Documents a real contract: the mount bridge rides on hydrate.)
- The fixture first sent `{ping:1}` **synchronously while still `CONNECTING`** — and the echo never came,
  because `ws.js` `send()` is a **deliberate no-op off `readyState===1`** (it never buffers; no unbounded
  queue, no ambiguous replay-on-reconnect). That's the correct minimal-secure contract — *the test* was wrong.
  Fixed the fixture to send on `onStatus("open")`, honoring the runtime's documented contract.

**Done — added `e2e/ws.spec.js` + the `/ws` fixture; full browser e2e now 8/8 PASS in 1.7 s.**
- New: `ctx.ws` lazy-loads `adh-ws.min.js`, connects, receives the server's open frame (JSON-parsed), sends
  `{ping:1}`, receives the echo — the complete RFC-0008 Phase 2 client round-trip, in a real engine.
- Regression-clean: the other 7 (#22) still green; 84/84 unit, typecheck clean, bundles in budget (core 5077 B
  / adh-ws 464 B gzip). Re-benchmarked: 6.0 µs/island hydrate, 4.45 µs/click.

**This closes the WS-client validation loop (north star #2):** #15 shipped it, #16 hardened reconnect, #22
proved the runtime broadly, and #23 proves the *one path #15 said it couldn't* — lazy-load + live socket — end
to end. The client side of RFC-0008's XHR+WebSocket ask is now built, hardened, AND browser-verified.

**Assessment (×3):** *Pro* — closes the single structurally-unverified path in the whole client; the
contract findings (hydrate-gates-mount, send-only-when-open) are real documentation value; ninth time a
"can't verify here" assumption dissolved on measurement. *Con* — verification + a test fixture, not new
shipping code; the runtime itself was already correct (the bug was in my fixture). *Consolidate* — the
no-op-while-connecting behavior is *right* (minimal, failure-safe); keep the runtime, fix the test to honor
the contract, record the green. Ship the e2e.

---

## Iteration #24 — 2026-06-21 (north star #1 finally has live numbers: a runnable ADServe + first baseline)

**Trigger:** fresh firing. Before deferring to the big DocC effort I flagged, re-measure the three north
stars' "blocked/under-served" claims — the loop's proven throughline (now 13×: a "blocker" dissolved on
measurement again this round).

**Re-measured — three findings, two that dissolved redundant work, one that unblocked the top star:**
- **#3 spare-parts:** still mid-`PersistenceADDB` refactor (29 uncommitted changes, the `ADSQL→ADDB` rename
  in flight). Confirmed blocked — do not disturb.
- **#2 ADHTML/Vue-maturity docs:** the *entire* DocC plan I was about to execute is **already done +
  committed** (`859d68e`: 2 catalogs, 9 articles, 947 lines + the comment cleanup). I then ran the plan's
  *deferred* headline check — `generate-documentation --warnings-as-errors` for both targets — and it builds
  **green, zero warnings** (all symbol links + Topics resolve). And it's **already CI-gated** (the `docs-check`
  job). So #2's docs are written ✓ committed ✓ build-verified ✓ AND never-rot-protected ✓. Nothing to add.
- **#1 ADServe perf:** the ordo-one micro-bench genuinely needs the benchmark plugin's pipe/TTY orchestration
  (sandbox-blocked) — BUT a Bun probe proved **port-binding + serving works here**. Only the *plugin* was
  blocked, never servers. The live-load path was viable all along.

**Done — built the missing piece + captured the first live numbers (north star #1):**
- ADServe was **library-only — no runnable server**, so "most performant" had zero end-to-end evidence. Added
  `Sources/ADServeBench` (ADSERVE_DEV-gated executable): a real server, TechEmpower-shaped routes through the
  full engine (envelope, keep-alive, idle timeout, connection limiter). Doubles as the canonical "how to run a
  server" example (a genuine gap). Plus `Benchmarks/loadtest.js` (dep-free Bun load generator) +
  `loadtest-baseline.md`. ADServe commit `7ee712d`; `swift-format` strict clean; build green (221 s release).
- **Baseline (the loop's "benchmark everything," finally answered for the server):** `/json` **74.9k req/s**,
  `/plaintext` **71.2k**, `/users/{id}` **68.2k** — all **0 errors**, **sub-ms p50**, **p99 < 1.8 ms** over
  357k requests. Param routing costs only ~9% over plaintext (the trie + one capture are cheap).
- **Honest caveat, documented:** throughput plateaus from c=16 (62k→67k across a 16× concurrency range) — the
  signature of a saturated single-process *client*, not the server (p99 stays ~1.6 ms on just 2 event loops).
  These are a **client-limited LOWER BOUND**; the server has more to give. Next: an open-loop tool (oha/wrk2)
  + a multi-process client to find the true ceiling, then Hummingbird/Vapor under the same harness for the
  comparative "most performant" claim.

**Assessment (×3):** *Pro* — fills a real gap (a server framework with no runnable server), produces the
session's first live req/s + latency for the #1-ranked, most-under-served star, and leaves a committed,
reproducible harness + baseline future iterations extend. *Con* — a single-client baseline isn't a
"most-performant" *proof* (needs competitors + open-loop); the numbers are client-limited. *Consolidate* —
ship the runnable server + harness + the honest lower-bound baseline now (durable, reusable), and name the
open-loop + comparative work as the explicit next step. The biggest unfulfilled directive finally has a real
answer.

---

## Iteration #25 — 2026-06-21 (the true ceiling: open-loop oha + event-loop scaling + an engine-default finding)

**Trigger:** #24's baseline was a single-client *lower bound* ("the server has more to give"). Find the real
ceiling — the explicit #24 next-step. Comparative-vs-Hummingbird is network-blocked (SPM can't fetch deps
offline), so the dep-free path is removing the client bottleneck.

**Re-measured — #24's own conclusion was half-wrong (14th correction-on-measurement):**
- **Bun multi-client (loopCount=2):** aggregate rps stays FLAT across 1→6 parallel clients (70k→70k→68k→62k).
  So the server was **saturated at ~70k on 2 loops** — server-bound, *not* client-bound as #24 inferred from
  the single-client plateau. The decline at 4–6 clients is CPU contention (clients stealing the server's cores).
- Added an **`ADSERVE_BENCH_LOOPS` knob** (the perf-critical event-loop count; engine `HTTPServer` default is
  2) so scaling is measurable. Rebuilt incrementally (6.9 s).
- A Bun loop-sweep showed a FLAT peak (~70–73k) across 2/4/8 loops — a co-located artifact: heavy JS client +
  server compete for 8 cores. So installed **oha** (Rust, open-loop, low client overhead — the SOTA tool) to
  free cores for the server.

**Done — clean oha scaling + per-route numbers (ADServe commit `0d373a4`):**
- **Event-loop scaling (/plaintext, 64 conn):** 1→**36.7k**, 2→**72.6k**, 4→**81.3k**, 8→**85.1k** req/s.
  **1→2 loops is near-linear** (the accept/serve path parallelizes cleanly); 2→8 diminishes — a co-located
  artifact (oha + server share 8 cores), not a server limit.
- **Per route @ 8 loops:** `/json` **89.3k**, `/plaintext` **87.6k**, `/users/{id}` **84.7k** req/s — sub-ms
  p50, p99 ~4 ms, **100% success**. Param routing costs only **~3%** (Bun's overhead had inflated it to 9%).
- oha sees ~87k where the Bun client capped at ~70k — the JS load generator *was* part of #24's ceiling.

**Finding (the "identify" pillar):** the engine's `HTTPServer` default **`loopCount: 2` leaves ~17%
throughput unused** on an 8-core host (72.6k vs 85–87k at 4–8 loops). An app constructing `HTTPServer`
without setting `loopCount` only uses 2 loops. Flagged for follow-up — may be a deliberate conservative
default for low-core/containerized targets, so it's a question to raise, not a unilateral change.

**Assessment (×3):** *Pro* — found the real ~87k ceiling + proved clean 1→2 scaling; the `loopCount` knob is a
genuine bench improvement; surfaced a concrete engine-default question; adopted the SOTA open-loop tool for
rigorous tails. *Con* — the multicore plateau is still co-located-capped (true ceiling needs a separate load
host); comparative numbers remain network-blocked. *Consolidate* — ship the knob + oha-measured baseline +
the engine-default finding; the separate-host + comparative work stays the named next step for #1.

---

## Iteration #26 — 2026-06-21 (the #25 finding, investigated → a real engine perf fix: loopCount default)

**Trigger:** #25 flagged `HTTPServer`'s `loopCount: 2` default as "maybe deliberate" and moved on — a deferral
without investigating *why*. Re-measure that assumption (the loop's whole throughline): is 2 deliberate, or
an oversight?

**Investigated — it's an oversight, and safe to fix:**
- The `= 2` default carries **no rationale comment** (every other tuned default — `maxBodyBytes`,
  `maxConnections` — documents its reasoning). `System.coreCount` is used **nowhere** in the engine, though
  it's the NIO / Hummingbird / Vapor convention for sizing a `MultiThreadedEventLoopGroup`.
- **Nothing depends on the default of 2:** every test constructs `HTTPServer` with `loopCount: 1` *explicitly*
  (deterministic single-loop testing). So changing the default can't regress the suite.
- **The container footgun is already handled:** `NIOCore.System.coreCount` is cgroup-aware — it honors Linux
  v1/v2 CPU quotas + cpuset before falling back to `_SC_NPROCESSORS_ONLN`. A constrained container gets its
  *quota*, not the host core count. That removes the one real objection to defaulting to coreCount.

**Done — changed the engine default (ADServe commit `a0d1a76`):**
- `HTTPServer` now defaults `loopCount` to a new `public static let defaultLoopCount = System.coreCount`
  (mirrors the existing `defaultMaxConnections` pattern; self-documenting doc comment with the cgroup note).
  The `ADServeBench` default + `loadtest-baseline.md` updated to match.
- **Verified end-to-end:** all **273 tests green** (no regression — the explicit `loopCount: 1` in tests is
  untouched); out-of-box `swift run ADServeBench` now serves **86.1k req/s** (was ~72k at the old default
  of 2) — a **~19% throughput gain with zero app-side tuning**, p50 0.54 ms, p99 4.2 ms, 100% success.

**This is the first engine-level perf *fix* of the loop (not just a measurement)** — and it's exactly what
the runnable bench from #24–25 was for: it surfaced a real default that under-utilized multicore, on the
#1-ranked star. Boilerplate reduced too (apps no longer must hand-tune `loopCount:` for sane multicore perf).

**Assessment (×3):** *Pro* — a concrete, verified ~19% out-of-box win on the top star; matches the
swift-server convention; cgroup-safe; removes app boilerplate; 273 tests prove no regression. *Con* — it's a
public-default behavior change (more event-loop threads by default), though that's the intended, conventional
behavior and is quota-bounded. *Consolidate* — the investigation cleared every risk (no test dependence,
cgroup-aware, documented), so ship the fix; the separate-host true-ceiling + comparative benchmarks remain #1's
next steps.

---

## Iteration #27 — 2026-06-21 (the "make safe" pillar: O_NOFOLLOW closes the static open's TOCTOU)

**Trigger:** the prism weights security heavily, and the carry-forward still listed static-serving hardening
from the early `/etc/passwd` audit (canonicalize root, symlink TOCTOU, extension allow-list, traversal tests).
Re-measure the *current* static defense before assuming any item is open.

**Re-measured — the static jail is far more hardened than the backlog implied (Nth time):**
- Paths are canonicalized via `standardizedFileURL` + `resolvingSymlinksInPath`, then jailed with
  `isInsideRoot` — for the identity file AND the `.br`/`.gz` precompressed siblings. So `..` and symlink
  *escape* are caught at plan time (P1 ✅).
- **Dotfiles are rejected at the engine level** (`.env`, `.git/config`) — even via a hand-built `.file()`
  route, with the engine as the final gate, not just the DSL. Regular-file-only. Every failure collapses to
  404 with no leak about why. The DSL also has an extension allow-list.
- The ONE genuine residual: `openForReading` opened with `O_RDONLY` only. The plan stats a symlink-resolved,
  jailed path, but a final component swapped to a symlink BETWEEN the stat and the open (an attacker racing a
  planted link to read outside the root) would be followed — a narrow TOCTOU.

**Done — O_NOFOLLOW on the static open (ADServe `897348d`):**
- `open(path, O_RDONLY | O_NOFOLLOW)`. **Provably non-breaking:** the plan only ever passes a symlink-resolved
  path, so a real asset's final component is never a symlink (a symlinked deploy root is resolved away before
  the open) — O_NOFOLLOW never rejects a legitimate file. It rejects only a final component that *became* a
  symlink after resolution (the race) → the open fails (ELOOP) → 404, like any other open failure.
- Added a direct unit test (`openForReadingRefusesAFinalComponentSymlink`): a regular file opens; a symlink to
  it — even an in-tree, otherwise-legitimate target — does not. **Full suite 274 green** (was 273), lint clean.

**Assessment (×3):** *Pro* — closes the last known gap in the static defense on the #1 star with a minimal,
SOTA, provably-safe change + a pinning test; exactly the "failure-safe / secure by default" the prism asks
for. *Con* — narrow value (TOCTOU needs a local attacker with write access to the served tree racing the
open); the bigger leak-vector decision (P2, default extension set) is breaking and stays an owner call. *Consolidate*
— ship the zero-risk hardening + the test now; P2 needs an explicit decision, not a unilateral default change.

---

## Iteration #28 — 2026-06-21 (the "avoid recursion" pillar finds a real one: an HTML-parse stack-overflow DoS)

**Trigger:** the prism explicitly says *avoid recursion*, and both cores advertise iterative engines — so check
where recursion actually lives, and whether any is unbounded over untrusted input. (Also re-checked spare-parts:
still 29 uncommitted, refactor in flight — #3 stays blocked, untouched.)

**Found — a genuine bug, not just a style nit:**
- The cores ARE rigorously iterative (ADR-0002, explicit stacks everywhere: renderer, wire serializer,
  expression eval, the route trie) with depth caps. As designed.
- The exception is the **crawl's HTML pipeline**. `HTMLTape` (tokenize) + `HTMLTreeBuilder` (tree-construct) are
  both iterative, so they fold an adversarial `<div>`×100000 page into a 100000-deep `HTMLNode` tree with **no
  nesting cap** (caps existed for name-length + attr-count, not depth). But the downstream passes —
  `markdown()`/`plainText()` (HTMLMarkdown) and `first(where:)`/`firstElement`/all-descendants (HTMLExtract) —
  walk that tree by **RECURSION with no depth guard**. The crawl parses UNTRUSTED pages, so a deeply-nested one
  **overflowed the native stack** — verified: the test process died with **signal 10 / SIGBUS**. A real
  reliability/DoS hole, and a violation of the codebase's own iterative-for-untrusted discipline.

**Done — single-point fix (ADHTML `b2e256c`):**
- Cap element-nesting depth in the tree builder: past the bound a start tag is coerced to a childless leaf
  instead of opening a frame, so the tree can never exceed it and **every downstream recursive walk inherits the
  protection at once** — no need to rewrite five walks. Cap **128**, sized for the RECURSIVE consumers: my first
  attempt reused the renderer's `defaultMaxDepth` 512 and **still crashed** (512-deep recursion overflows a
  ~512 KiB worker-thread stack — the renderer's 512 is safe only because IT is iterative). 128 is well under
  that stack yet far deeper than real documentation HTML nests.
- Test: 20_000 nested `<div>` parses to a tree bounded ≤130 deep, and `markdown()`/`plainText()` complete
  without crashing and still surface the innermost text. **Full suite 254 green** (was 253), lint clean.

**Assessment (×3):** *Pro* — a real, verified stack-overflow DoS on untrusted input, fixed at the single choke
point so all consumers are covered; the cap value was empirically derived (the 512 attempt crashing taught the
recursive-vs-iterative distinction); restores the codebase's own ADR-0002 discipline. *Con* — a build-time
crawl feature (blast radius is "crash the build," not the server); the walks are still recursion (now bounded,
the CSSScoper precedent) rather than rewritten iterative — a fuller fix if the crawl ever moves to request time.
*Consolidate* — the bounded-depth cap is the minimal, correct, failure-safe fix now; note iterative walks as the
follow-up if the threat model escalates.

---

## Iteration #29 — 2026-06-21 (close the CLASS: a full-pipeline HTML-parse robustness gate)

**Trigger:** #28 fixed one DoS *instance*; bug classes cluster in untrusted parsers, and the prism asks for
"CI/buildtime/runtime (through checks)" + failure-safe. So check the parser's actual fuzz coverage — why
didn't the existing suite catch #28?

**Re-measured — a real coverage gap:**
- ADHTML *does* fuzz the HTML parser, but `HTMLTapeRobustnessTests` only exercises the **tokenizer** — it stops
  at `HTMLTape.build(html).materialize()` (tokens), never reaching `HTMLNode.parse` (tree-build) or the
  recursive `markdown()`/`plainText()`/`first(where:)` walks — and its inputs are ≤256 random chars / ≤40
  balanced tags (never deep). That's exactly why #28's deep-nesting overflow slipped through: the gate didn't
  cover the layers that overflowed, nor feed adversarially-deep input.
- ADTestKit already ships the right tools — `runOnConstrainedStack` (512 KiB worker stack) + `DepthSweep` — and
  ADServe has a precedent (`MultipartParser.parse on a 512 KiB stack survives adversarially deep input`). The
  gap was just that ADHTML's parse pipeline had no equivalent.

**Done — added `HTMLParseRobustnessTests` (ADHTML `56e8e11`):**
- **Constrained-stack DepthSweep** (the #28 regression lock): pins a 512 KiB stack — the main multi-MB test
  stack would *mask* a regression — and sweeps depths straddling the tree-builder cap up to 1_500 (several×
  past the ~512 frames at which these walks overflow uncapped) across three nesting shapes (div, list, quote).
  Reaching the end proves the cap keeps the recursion bounded.
- **Full-pipeline soup fuzz:** random metacharacter soup + random (un)balanced tag streams through
  `parse()` + the three walks; any crash/OOB/hang fails, seeded for replay. Covers the tree-build + walk layers
  the tape-only fuzz can't reach.
- **256 tests green** (was 254), lint clean. Tuning: the depth test was **60 s** at `upTo: 20_000` (the
  over-cap leaf-width × the string-building walks); dialed to `upTo: 1_500` → **4 s**, still 3× past the
  overflow threshold — measured, not guessed.

**Assessment (×3):** *Pro* — closes the *class* #28 was one instance of, with a constrained-stack lock that
actually reproduces the failure mode (the main stack hides it) + a full-pipeline fuzz, both reusing the
codebase's own ADTestKit harness + ADServe precedent; a real CI/failure-safe improvement. *Con* — pure test
infrastructure (no shipping code), and the depth test adds ~4 s to a 0.17 s suite (justified: it spawns real
worker threads at multiple depths × shapes — comparable to ADServe's fuzz suite). *Consolidate* — ship the
gate; it's the durable guard that turns #28 from a one-off fix into a permanent invariant.

---

## Iteration #30 — 2026-06-21 (the comparative truth: ADServe vs Hummingbird → a real perf fix)

**Trigger:** north star #1 is "most performant OUT THERE" — which needs COMPARATIVE evidence, deemed
"network-blocked" all session. Re-measure that assumption (the loop's signature move). (Also re-checked
spare-parts: still 29 uncommitted, blocked; and verified the ADHTMLMarkdown recursion is SAFE — `MarkdownString`
is author-trusted with no untrusted-string interpolation, so the #28 DoS pattern was unique to the crawl.)

**Re-measured — the network is OPEN for public repos (15th dissolved assumption):** `git ls-remote
hummingbird` returns its HEAD; the earlier auth error was only for PRIVATE AD* deps (provided via local
paths). So the comparative benchmark was never actually blocked.

**Done — built it + it found a real fix (ADServe `4711618`+`a90eb99`):**
- Fetched **Hummingbird 2.25** (the closest NIO peer), built a server with ADServeBench's exact routes, and
  benchmarked both ALONE under the identical oha harness (default config, ≈core-count loops both). **Honest
  result: ADServe trailed — `/plaintext` 87.7k vs Hummingbird's 117.5k (~34%).** ADServe is NOT yet the
  fastest. (Used WebFetch for the HB API — the apple-docs MCP doesn't index third-party frameworks.)
- **Localized via `sample` profiling under load:** the hot ADServe frames were `build_tree` (zlib Huffman
  construction), `MIMEDatabase.isCompressible`, `_stringCompare*` — ADServe was **gzip-compressing a 13-byte
  body**. The compression predicate gated on MIME + not-206 but had **no size floor**. Probe confirmed:
  `Accept-Encoding: identity` → 106k vs gzip → 88k.
- **Fixed:** a `gzip_min_length`-style size gate (`minimumCompressibleResponseBytes = 1400`, one MTU) — a
  sub-MTU body is one packet either way, so compressing it only burns CPU and can enlarge it. `/plaintext`
  recovered **88k → ~99–106k** (the identity ceiling), narrowing the HB gap **~34% → ~15%**. Verified
  deterministically (a 13-byte gzip-accepting response now carries no `Content-Encoding`; a 3 KB body still
  gzips) + a new regression test + **274 tests green**.

**This is the most consequential #1 finding of the loop:** it turned "is ADServe the most performant?" from an
untested claim into a measured answer (no — it trails Hummingbird), and the measurement immediately yielded a
real, correct optimization. The **residual ~15% is the core per-request path** (per-request active-count
atomics + response-head materialization vs HB's leaner handler) — now the explicit, well-directed #1 target.

**Assessment (×3):** *Pro* — finally produced the comparative evidence #1's literal goal demands, and the act
of measuring found + fixed a genuine, universally-correct inefficiency (compressing tiny bodies); the gap is
now quantified + half-closed with a clear next step. *Con* — the comparison is default-vs-default (HB is leaner
out of the box; a feature-matched run is fairer), co-located (both equally), and ADServe still trails. *Consolidate*
— ship the fix + the honest comparison; the residual core-path gap + a Vapor leg + a feature-matched HB run are
the named next #1 steps. Honesty over a flattering number.

---

## Iteration #31 — 2026-06-21 (user-requested: a 5-way cross-stack benchmark — ADServe is LAST)

**Trigger:** the user asked to set up an Erlang server + another known-fast server and compare with Hummingbird.
Installed Erlang (OTP) + Go (brew), wrote four tiny servers with ADServeBench's exact routes — Bun (`Bun.serve`
`routes`), Go `net/http`, Erlang raw `gen_tcp` with `{packet, http_bin}` + process-per-connection, plus the
existing Hummingbird — and benchmarked all five ALONE under the same oha (`-z 5s -c 64`, best-of-2).

**Result (/plaintext req/s, ADServe with the iter-#30 gzip fix):**
`Bun 203.8k > Go 162.9k > Erlang 142.9k > Hummingbird 114.7k > ADServe 102.4k`.

**Honest read — ADServe is the SLOWEST of the five** (tracked in `ADServe/Benchmarks/loadtest-baseline.md`,
commit `7d0f23b`). Two gaps: (1) **within Swift/NIO** ADServe trails Hummingbird ~11% — same runtime, so it's
purely ADServe's heavier per-request path (the closeable #1 target); (2) **cross-language** Go/Erlang/Bun are
1.4–2.0× faster — partly the comparison shape (raw `gen_tcp`, Bun's precompiled `routes`, Go's decade-tuned
stdlib) and partly real runtime cost (Swift ARC + the NIO `ChannelHandler` pipeline vs goroutines / BEAM
processes / Bun's Zig core). Closing to Hummingbird is realistic; matching Bun/Go is much deeper (or a ceiling).

**Assessment (×3):** *Pro* — answers the user's question with real data + the strongest possible context (4
peers across 4 runtimes); makes #1's true standing unambiguous + the within-Swift gap the concrete target.
*Con* — humbling (ADServe is last), and the cross-language legs aren't perfectly feature-matched (raw vs
framework). *Consolidate* — report it straight; the honest standing is more useful than a flattering subset.
The external servers are throwaway (recipes in the baseline doc); nothing competitor-related enters the repos.

---

## Iteration #32 — 2026-06-21 (the breakthrough: SwiftNIO IS the bottleneck — raw Swift is ~2× faster)

**Part A — a dead end, honestly closed.** Chased the within-Swift gap by micro-optimizing the per-request
response path: `commonHeaders` rebuilt the envelope's backing array + re-hashed every field name into a fresh
index map on EVERY response, so I made it COW-copy the prebuilt `envelope` instead. Correct + 275 tests green
— but an A/B with a realistic 7-header envelope showed **93.2k vs 93.7k, pure noise**. The per-request header
construction is NOT the bottleneck. **Reverted** (no measured benefit + it reordered response headers). Kept
only the useful `ADSERVE_BENCH_ENVELOPE` bench knob (`47c8d55`).

**Part B — the user's hypothesis, tested + CONFIRMED.** The user: *"the reason we're slower is swiftnio, we
should go from scratch"* + *"forget about linux."* Built a from-scratch **raw-Darwin-socket** HTTP/1.1 server
(`ADServe/Benchmarks/raw-spike`, ~80 lines, no NIO: thread-per-connection, blocking I/O, hand-rolled request
parse, `TCP_NODELAY`). Result (best-of-5, oha `-c 64`):

`Bun 203.8k > **raw-swift 196.8k** > Go 162.9k > Erlang 142.9k > Hummingbird(NIO) 114.7k > ADServe(NIO) 94.6k`.

**The raw Swift server is ~2.08× faster than NIO-ADServe and ~1.7× faster than NIO-Hummingbird — second
overall, behind only Bun.** Both NIO servers sit at the bottom; raw Swift vaults to the top. So **Swift/ARC is
NOT the floor — the NIO `ChannelHandler` pipeline is ~half the throughput** on this micro-workload. The user
was right. (`ADServe` commit with the spike + finding in `loadtest-baseline.md`.)

**Caveats (honest):** tiny-response keep-alive is the BEST case for raw (TLS / HTTP-2 / large bodies shrink the
gap); the spike has no TLS, no robust parsing/limits/timeouts. A production from-scratch transport must
re-provide what ADServe needs — and **TLS must never be hand-rolled** (Darwin → `Network.framework`).

**Assessment (×3):** *Pro* — a decisive, measured answer to the #1 north star: the path to "most performant" is
a Darwin-only from-scratch transport (~2× headroom proven), NOT micro-tuning NIO (a dead end, A/B-confirmed).
*Con* — it's a major architectural commitment; the spike is a happy-path best-case; re-providing NIO's TLS /
HTTP-2 / robustness / cross-platform is real work (mitigated: Linux is now out of scope). *Consolidate* — ship
the spike as preserved evidence; the next step is to measure the PRODUCTION transport candidate
(`Network.framework`, which gives TLS + perf) before building it out — measure before committing the rewrite.

---

## Iteration #33 — 2026-06-21 (de-risk the rewrite: Network.framework RULED OUT, raw sockets confirmed)

**Trigger:** #32's consolidate — before committing to a from-scratch rewrite, measure the PRODUCTION transport
candidate. The obvious one is Apple's **`Network.framework`** (NWListener/NWConnection): it gives TLS, TCP
options, and connection management for free, which the raw kqueue spike lacks. Is it as fast as the spike?

**Found — no. Network.framework is SLOWER than NIO** (`Benchmarks/raw-spike/server-networkframework.swift`,
3-way, oha `-c 64`):
- raw-swift (raw sockets): **178.1k**, p50 0.35 ms
- ADServe (NIO): 97.6k, p50 0.37 ms
- **nw-swift (Network.framework): 89.9k, p50 0.81 ms** — slower than NIO, **2.3× the latency**, half the raw
  throughput. Its NWConnection / dispatch-queue model adds real per-request overhead.

So the "TLS for free" path does NOT deliver the win — **ruled out.** The fast transport is **raw sockets**.

**Architectural consequence (the key output):** raw sockets give no TLS — but ADServe's canonical deployment is
**proxy-fronted** (Caddy terminates TLS + adds `Date`), so a raw *plaintext* HTTP/1.1 engine needs no
in-process TLS for that case. The shape: a from-scratch raw-Darwin engine as the **plaintext fast path**, the
existing **NIO engine retained for direct-TLS / HTTP-2** (a feature path where the perf delta matters less),
both under ADServe's HTTP semantics (routing DSL, security envelope, response model, static/path hardening, the
275 tests). Production-grade = a robust parser + limits/timeouts/backpressure + a **kqueue reactor** (vs the
spike's thread-per-connection) for connection scaling.

**Assessment (×3):** *Pro* — measured the obvious-but-wrong path BEFORE building it (saved a Network.framework
rewrite that would have shipped *slower* than today); the architecture is now evidence-shaped (raw + proxy-TLS,
NIO fallback), not guessed. *Con* — still pre-build; the real engine (robust parser, kqueue reactor,
integration) is the large multi-iteration effort ahead. *Consolidate* — two spikes now bound the design (raw =
fast, Network.framework = no); next is the production raw engine, phased + benchmarked against the ~178–197k
ceiling, starting from the proxy-fronted plaintext path.

---

## Carry-forward backlog (the "identify" pillar — fuel for later iterations)

**ADServe — security / robustness**
- ✅ **Static jail is comprehensively hardened** (re-measured iter #27 — far more complete than this backlog
  implied): canonicalize + `resolvingSymlinksInPath` + `isInsideRoot` jail (identity AND `.br`/`.gz` siblings),
  **engine-level dotfile rejection** (`.env`/`.git` even via a hand-built `.file()` route), regular-file-only,
  every failure → 404 (no info leak), and a DSL extension allow-list. **O_NOFOLLOW on the open landed iter #27**
  (`897348d`), closing the last residual (open-time TOCTOU symlink swap) — provably non-breaking (the plan only
  passes symlink-resolved paths) + a direct unit test. 15 `PathTraversalTests` green.
- *(remaining, lower priority)* **P2** — tighten the DEFAULT servable extension set (drop `.txt`/`.json`/`.map`/
  `.xml`, leak vectors under a misconfigured dir root): **breaking**, needs an explicit owner decision + opt-in.
  **P1** — a build-time *warning* for a `root` escaping the project CWD (dev ergonomics, NOT a runtime hole; the
  jail already contains it at runtime). **P5** — assert `root` absolute in `isInsideRoot` (belt-and-suspenders).

**ADServe — performance (north star #1)**
- **Live-load baseline + scaling CAPTURED (iters #24–25):** `ADServeBench` (runnable server, `ADSERVE_BENCH_LOOPS`
  knob) measured with **oha** → ~**87k req/s** (`/json` 89.3k), sub-ms p50, p99 ~4 ms, 100% success at 8 loops;
  **1→2 loops near-linear**; param routing ~3% over plaintext (`ADServe` `7ee712d`+`0d373a4`, tracked in
  `Benchmarks/loadtest-baseline.md`). Only the ordo-one *plugin* sampling is sandbox-blocked, so the micro-bench
  `routing/*`/`percent/*`/`mime/*` tables still want a clean host / CI.
- ✅ **COMPARATIVE BENCHMARK DONE (iter #30) — ADServe trails Hummingbird ~15%** (after the gzip fix; ~34%
  before). Network is NOT blocked for public deps. ADServe `/plaintext` ~99–106k vs Hummingbird 2.25 ~117.5k.
  The `gzip_min_length` fix (`4711618`) closed half the gap; the **residual ~15% is the core per-request path**
  (per-request active-count atomics + response-head materialization) — the live #1 target. Next: profile/trim
  that path; add a Vapor leg + a feature-matched HB run.
- ✅ **RESOLVED (iter #26) — engine `loopCount` default:** `HTTPServer` now defaults `loopCount` to
  `defaultLoopCount = System.coreCount` (was hardcoded 2). Investigation cleared every risk (no rationale for
  2; every test pins `loopCount: 1` explicitly so nothing regressed; `System.coreCount` is cgroup-aware →
  container-safe). Out-of-box throughput 72k → **86.1k** (~19%), 273 tests green (`ADServe` `a0d1a76`).
- `pathMatchesExact` made allocation-free (iter #2). Next: scan other DSL hot paths for incidental
  allocations the malloc gate would catch.

**ADHTML — Vue maturity (north star #2)**
- RFC-0008 Phase 1 `ctx.fetch` DONE (iter #3). **Server WS HARDENED + COMPLETE** (iters #4–6, #8, #10): CSWSH
  gate + `WebSocketHub` (broadcast + auto-prune) + `Channel` (subscribe-only + typed-inbound). Only the CLIENT
  remains: `ws.js` + `ctx.ws` as an OPT-IN module, **gated on a build-system code-split** (core at 4.92/5 KiB):
  `build.js` → a second `adh-ws` bundle the core lazy-loads via `import(new URL("./adh-ws.js", import.meta.url))`,
  per-chunk budget, the test resolving `./ws` from source. ADR-sized; its browser lazy-load isn't verifiable
  in this sandbox. Smaller deferred sugar: per-route cross-origin WS allowlist; `App(cors:)`.
- **North star #1 (perf) is now the prime under-served target** — touched only once (iter #2, the
  `pathMatchesExact` alloc). The malloc-tracked ordo-one harness is healthy but the sampling run is
  sandbox-blocked; a hot-path allocation hunt is still reason-verifiable by inspection.
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
