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
- No perf baseline exists yet ("benchmark everything"). Need a load harness (wrk / bombardier / `swift-nio`
  bench) + a tracked baseline (req/s, p50/p99, allocations) so each iteration can prove non-regression.

**ADHTML — Vue maturity (north star #2)**
- RFC-0008 Phase 1 is the next build: generalize `action.js`'s `request()` into a JSON transport +
  `ctx.fetch`; add an ADServe CORS surface (web↔api cross-port). Then Phase 2: `ws.js` + `ctx.ws` + ADServe
  typed `Channel`. No client WebSocket exists today; the mount `ctx` is `{root, action}` only.
- Boilerplate: the 7 verb-overload pairs in `ServerDSL.swift` are near-identical — a candidate for a macro
  (the prism's "macros where relevant" / "reduce boilerplate"). Assess before doing (macros add build cost).

**spare-parts-app (north star #3)**
- Audit which ADRs/RFCs are implemented vs pending (the app's `docs/adr` + `docs/rfcs`), turning #3 into a
  tracked checklist. Blocked on the user's in-flight `PersistenceADDB` refactor settling — do not disturb.

**CI / buildtime / runtime**
- ADServe pre-commit runs SwiftLint + swift-format strict (good). Confirm the same gate exists in ADHTML +
  the app, and that CI runs the full suites with the `AD*_PATH` env. Consider a `--warnings-as-errors` gate.
