# RFC 0007 — Production-readiness roadmap (ADHTML × ADServe → 1.0)

- **Status**: Accepted (living roadmap)
- **Date**: 2026-06-20
- **Related**: ADR-0012 (ADServe integration), `docs/integration/adserve-requirements.md`, RFC-0005
  (authoring ergonomics), RFC-0006 (client dynamic/async/JS), RFC-0003 (reactivity/hydration),
  ADR-0006/0011 (runtime/SRI), ADR-0013/0014/0015. ADServe repo: branch `feat/production-complete`.
- **Scope**: everything required to take **both** ADHTML and ADServe to a production-ready 1.0, grounded
  in a ground-truth audit of both repos (not the docs, which were found stale).

## 1. Executive summary — the surprising true state

Two repos, two stale-doc traps, and a much better reality than either README implies:

- **ADHTML** is **not a skeleton.** Render core, escaping, reactivity, islands + hydration, the wire
  format, the `@Component`/`@State`/`#attr` macros, streaming, SRI, and the 2.2 KiB JS runtime are
  implemented and pass **64 Swift tests + 23 JS tests + 3 chromium e2e** (the README claimed "skeleton";
  corrected 2026-06-20).
- **ADServe** is **not missing the transport primitives.** A ground-truth audit (105 tests passing on
  `feat/production-complete`) shows **all six** capabilities the integration doc lists as "Missing" are in
  fact **shipped**: `.html()` + `MediaType.html`, `.stream` (back-pressured `ResponseBodyWriter`), `.sse`
  (WHATWG framing + heartbeat + disconnect cancellation + concurrency limit), `Static` (ETag/304/Range/
  precompressed/symlink-jail; allow-list already includes `js`/`mjs`/`wasm`), and `CSPNonce` (128-bit per
  request + `strictHydrationPolicy`). The async seam ADHTML needs lives in the `.stream`/`.sse` body
  closures. **`docs/integration/adserve-requirements.md` is stale** and is corrected alongside this RFC.
- **The real critical path is small and unblocked:** the **`ADHTMLNIO` bridge** — a thin forwarder from
  ADHTML's `AsyncHTMLByteSink` to ADServe's `ResponseBodyWriter` (both `write(_ [UInt8]) async throws`,
  shaped 1:1 *on purpose*) plus a few `ResponseContent` conveniences. ADServe needs **no change** to
  support it. Once it lands, the full two-tier model **plus live SSE `patch`/`morph`** works end to end.

So "production ready" is mostly **integration + polish + ops**, not core engineering. This RFC enumerates
all of it and sequences it into milestones with a definition of done.

## 2. Ground-truth status

### ADHTML (this repo)
| Area | Status |
|---|---|
| Render core, escaping (text/attribute/url) | ✅ implemented + tested |
| Reactivity (Signal/Computed/CellArena/Reactive DSL) | ✅ |
| Islands + hydration + wire format v1 | ✅ |
| Macros (`@Component`/`@State`/`#attr`) | ✅ |
| Streaming primitive (`AsyncHTMLByteSink`) | ✅ |
| SRI (`ADHTMLSRI`), Fuzz harness | ✅ (gated) |
| JS runtime (2.2 KiB), typed attribute enums, typed events | ✅ |
| `.css` / `.scriptJSON` escape contexts | ⚠️ fail-safe stubs (over-escape; not unsafe) |
| Reactive cells: object/array values | ❌ scalars only |
| Stable `CellID` (hash of render-scope path) | ❌ Phase-1 = creation index |
| `ADHTMLNIO` ADServe bridge | ❌ empty placeholder (the critical path) |
| `ADHTMLMarkdown`, `ADHTMLObservability` | ❌ empty placeholders |
| DSL ergonomics (RFC-0005): implicit islands, `@Derived`, scope inference, … | ◻️ planned (enums + typed events done) |

### ADServe (sibling, `feat/production-complete`, 105 tests green)
| Area | Status |
|---|---|
| NIO h1+h2, TLS 1.3, routing trie, middleware (async), error/problem+json | ✅ |
| `.html` / `.stream` (`ResponseBodyWriter`) / `.sse` (`SSEWriter`) | ✅ |
| Static assets (ETag/304/Range/precompressed/jail; js/mjs/wasm allow-listed) | ✅ |
| `CSPNonce` + `strictHydrationPolicy`, security headers, CORS | ✅ |
| Graceful drain, conn/SSE limits, timeouts, body caps, compression (h1) | ✅ |
| Sessions/cookies, forms (multipart + urlencoded), rate limiting | ✅ |
| Observability (logging built-in; metrics+tracing opt-in target) | ✅ |
| Health/readiness **route helper** (primitive `ServerReadiness` exists) | ⚠️ app wires its own route |
| mTLS (M4), TLS-over-`.network` (F3b), HTTP/3 | ❌ deferred/gated |
| Deployment artifacts (Dockerfile/compose/k8s), load/stress tests | ❌ absent |
| ADRs/RFCs (decisions live in git history + code comments) | ❌ none in-repo |
| `Package.resolved` pinning of AD* siblings | ⚠️ planned (only apple/swift-server pinned) |
| ADHTML-aware code | ❌ none (by design — the bridge is ADHTML-side) |

## 3. Critical path — the `ADHTMLNIO` bridge (now unblocked)

A new gated target (`ADHTML_NIO`) `ADHTMLNIO` depending on `ADHTMLCore` + `ADServeCore`:

1. **Sink adapter.** Wrap an ADServe `ResponseBodyWriter` as an ADHTML `AsyncHTMLByteSink` — a direct
   forwarder (`write(_ [UInt8])` ⇄ `write(_ [UInt8])`; `flush()` ⇄ `flush()`). Buffers from
   `ADFCore.ByteBufferPool`.
2. **Response conveniences** (on ADServe's `ResponseContent`, via the bridge):
   - `.adhtml(_ view, arena:)` — buffered `renderHydratable` → `.html(bytes)`.
   - `.adhtmlStream(_ view, arena:)` — `.stream(contentType: .html) { writer in render into the adapter }`
     (TTFB; `<head>` flush; back-pressure already handled).
   - `.adhtmlSSE(...)` — drive live `morph`/`patch` frames over `.sse` (ADHTML serializes patches via
     `ADJSONCore.JSONMergePatch`; ADServe frames + writes).
3. **CSP wiring.** Handler reads `CSPNonceKey` from `RequestStorage` and stamps the inline state
   `<script nonce=…>` + the runtime `<script>`; ADServe emits the matching `script-src 'nonce-…'`.
4. **Static runtime.** Document the one-liner: `Static("/assets", root:)` serves the SRI-pinned
   `adh-runtime.min.js` (allow-list already covers `.js`).
5. **Integration tests** (new, gated): an ADHTML page served via `.adhtml`/`.adhtmlStream` round-trips
   over loopback (h1 + h2); an `.adhtmlSSE` stream delivers a `morph` and a `patch` and tears down on
   disconnect. **This is the first end-to-end proof of the whole stack.**

Depends on **stable `CellID`** (§4) for reliable SSE morph targeting across renders.

## 4. ADHTML — remaining work to 1.0

| Item | Why | Effort |
|---|---|---|
| **`ADHTMLNIO` bridge** (§3) | the integration; unlocks live updates | M |
| **Stable `CellID`** (XXH64 of render-scope path, RFC-0003 §2) | SSE morph/patch must target cells across renders | M |
| **`.css` + `.scriptJSON` dedicated encoders** | finish escape-by-default (today: fail-safe stubs) | S–M |
| **Object/array-valued reactive cells** | real app state (lists, records) | M |
| **DSL ergonomics (RFC-0005):** implicit islands, `@Derived` + wider expr set, scope inference, reactive interpolation, `$state`, doc/head conveniences, component slots | SwiftUI-grade authoring | L |
| **Client dynamic/async/JS (RFC-0006):** show/hide + attr bindings, custom-behavior registry + mount hooks, hypermedia actions (`fetch`→`morph`, ADServe-ready), async UX states | dynamic + networked + extensible | L |
| **`ADHTMLObservability`** render metrics/tracing hooks | prod visibility | M |
| **`ADHTMLMarkdown`** (optional for 1.0) | content sites | M |
| **Docs:** DocC catalog + tutorials + the multi-file example app (`Examples/Storefront`) + adoption guide | adoption | M |
| **Testing:** browser e2e + fuzz **in CI**; SSE integration tests (post-bridge); commit ordo-one baselines | confidence | M |
| **Perf:** `Span`/`RawSpan` escaper, ADJSON `SWAR` de-dup, committed baselines | the last perf items (ADR-0013) | M |
| **Accessibility:** typed ARIA (done) + a11y guidance + example coverage | inclusive + table-stakes | S |
| **API freeze + semver + CHANGELOG + deprecation policy** | 1.0 contract | S |

## 5. ADServe — remaining work to 1.0

| Item | Why | Effort |
|---|---|---|
| **Health/readiness route helper** (`/livez`/`/readyz` from `ServerReadiness`) | orchestrators need it built-in | S |
| **mTLS / client-cert auth (M4)** | zero-trust / service mesh | M |
| **TLS over `.network` transport (F3b)** | TLS on the NIOTransportServices path | M |
| **Deployment artifacts** (Dockerfile, compose, k8s manifests, healthcheck wiring) | shippable | M |
| **Load/stress tests + committed benchmark baselines** (`.benchmarkBaselines/`) | perf SLOs, regression gate | M |
| **HTTP/3** (`AD_HTTP3`, swift-nio-http3) | optional for 1.0 | L |
| **Decision docs (ADR/RFC)** — none in-repo; roadmap is in git history | maintainability/governance | S |
| **`Package.resolved` pinning of AD* siblings** | reproducible builds | S |
| **h2 response compression** (precompressed-static or proxy guidance) | parity with h1 | S |

## 6. Cross-cutting

- **Security (end-to-end):** CSP nonce wired through the bridge (§3.3); SRI on the runtime (done); finish
  `.css`/`.scriptJSON` encoders (§4); SSE concurrency + heartbeat + disconnect (ADServe ✅); CSRF for
  forms (ADServe sessions ✅ — wire a token helper); body/stream caps (✅). Run a combined threat-model
  pass before 1.0.
- **Observability (end-to-end):** ADServe metrics/tracing (✅ opt-in) + `ADHTMLObservability` render
  spans → one trace from request to rendered bytes.
- **CI matrix:** macOS + **Linux** for both repos; add the **cross-repo integration job** (ADHTML view
  served by ADServe) once the bridge lands; browser e2e + fuzz on a schedule.
- **Stale-docs cleanup:** README (✅ fixed), `adserve-requirements.md` (fixed with this RFC); add ADServe
  decision docs; keep ADR-0013 as ADHTML's status source of truth.
- **Release/versioning:** coordinated semver across the AD* family; pin `Package.resolved` everywhere;
  publish tags so consumers don't track `branch: main`.

## 7. Milestones

| Milestone | Contents | Outcome |
|---|---|---|
| **M1 — Wire it together (live end-to-end)** | `ADHTMLNIO` bridge (§3) + stable `CellID` + CSP wiring + cross-repo integration tests | A real ADHTML app served by ADServe with **live SSE updates** — the headline unblock |
| **M2 — SwiftUI-grade authoring** | RFC-0005: implicit islands, `@Derived` + wider expr, scope inference, reactive interpolation, doc/head, slots; ship `Examples/Storefront` | Apps written with no `Island`/`scope`/`.id` ceremony |
| **M3 — Dynamic + networked + extensible** | RFC-0006 phases 1–2 (show/hide, custom behaviors, mount hooks) + hypermedia actions (ADServe-ready) + async UX | Real dynamic/async UIs + sanctioned author JS |
| **M4 — Completeness & hardening** | `.css`/`.scriptJSON` encoders, object/array cells, observability both sides, perf (Span escaper + baselines), fuzz/e2e in CI, a11y guidance, ADServe health route + mTLS | Feature-complete, observable, benchmarked |
| **M5 — Ops & 1.0** | ADServe deployment artifacts + load tests + TLS-over-network; Package.resolved pinning; DocC tutorials + adoption guide; API freeze + CHANGELOG; coordinated **1.0** tags | Deployable, documented, versioned 1.0 |

## 8. Definition of done (1.0)

- A documented sample app renders **static + island** pages **and** receives **live SSE `morph`/`patch`**
  through ADServe, under a **strict CSP** (nonce) with an **SRI-pinned** runtime.
- Escape-by-default complete (dedicated `.css`/`.scriptJSON`); object/array cells supported; stable
  `CellID`.
- Authoring is SwiftUI-grade (implicit islands + `@Derived`); the example app uses no `Island`/`scope`.
- Both repos: green CI on macOS + Linux, the cross-repo integration job, committed perf baselines, fuzz
  on schedule; ADServe deployable (container + health + load-tested) with mTLS.
- Docs: DocC + tutorials + adoption guide; no stale status; ADServe decision docs exist.
- Public API frozen, semver + CHANGELOG, `Package.resolved` pinned, coordinated 1.0 tags.

## 9. References

- `docs/integration/adserve-requirements.md` (corrected), ADR-0012, RFC-0003/0005/0006, ADR-0013/0014/0015.
- ADServe `feat/production-complete` (ground-truth audit 2026-06-20): `ResponseContent` (`.html`/`.stream`/
  `.sse`/`.file`), `ResponseBodyWriter`/`SSEWriter`, `Static`/`File`, `CSPNonce`/`strictHydrationPolicy`.
