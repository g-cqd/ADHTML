# What ADHTML needs from ADServe

- **Status**: ✅ **Satisfied** — a ground-truth audit of ADServe (`feat/production-complete`, 105 tests
  green, 2026-06-20) found **all six** capabilities below are **already implemented**. The remaining work
  is the ADHTML-side **`ADHTMLNIO` bridge** (a thin forwarder), tracked in **RFC-0007** (production-
  readiness roadmap, §3). This document is kept as the capability contract + verification checklist.
- **Date**: 2026-06-20 (status corrected after audit; the original draft listed these as "Missing").
- **Related**: ADHTML ADR-0012, ADR-0006, RFC-0003, **RFC-0007**. Grounded in the actual ADServe
  `ADServeCore.swift` (`ResponseContent`, `ResponseBodyWriter`, `SSEWriter`), `ServerDSL.swift`
  (`Static`/`File`), `Middleware.swift` (`CSPNonce`). NOTE: there is **no ADR-0046 in ADServe** — its
  design intent lives in code comments + commit milestones (M0–M3), not numbered ADRs.

> **Correction:** the original draft of this file (and the §1–§6 "Add this" snippets below) predated
> ADServe's M0–M3 work and described these as missing. They are **shipped** — ADServe even shaped
> `ResponseBodyWriter.write(_ [UInt8])` to match ADHTML's `AsyncHTMLByteSink.write(_:)` 1:1 so the bridge
> is a direct forwarder. Read §1–§6 as "the shipped contract," not "to-do."

This is the contract ADHTML needs the **host** (ADServe) to provide. ADHTML renders bytes and emits a
hydration wire format + a static client runtime; **ADServe transports them**. The split is deliberate
(ADR-0012): the engine stays persistence- and transport-agnostic; the host owns sockets, streaming,
SSE, and static files.

## TL;DR

| # | Capability | Why ADHTML needs it | ADServe today | ADHTML-side bridge work |
| --- | --- | --- | --- | --- |
| 1 | `text/html` `MediaType` (+ `.html(_:)`) | Serve pages/fragments with the right content-type | ✅ `MediaType.html` + `.html(_:status:)` | use it |
| 2 | Streaming response (back-pressured byte sink) | Flush `<head>` + stream rows (TTFB; bounded memory) | ✅ `.stream` + `ResponseBodyWriter.write(_ [UInt8])` (matches our sink 1:1) | forward `AsyncHTMLByteSink` → writer |
| 3 | Server-Sent Events (`text/event-stream`) | Push live `morph`/`patch` to islands (RFC-0003) | ✅ `.sse` + `SSEWriter` (framing, heartbeat, disconnect-cancel, limit) | drive frames from the change feed |
| 4 | Guarded static-asset serving | Serve `adh-runtime.min.js` (+CSS/SVG) with ETag/304/SRI | ✅ `Static`/`File` (ETag/Range/precompressed/jail; `js`/`mjs`/`wasm` allow-listed) | `Static("/assets", root:)` |
| 5 | Async handler path | #2/#3 are async | ✅ async lives in the `.stream`/`.sse` body closures + middleware (handlers stay sync by design) | render inside the async body |
| 6 | Per-request CSP nonce | Inline state `<script>` + runtime under a strict CSP | ✅ `CSPNonce` middleware + `strictHydrationPolicy` + `CSPNonceKey` storage | read the nonce, stamp `<script nonce>` |

**All six are implemented in ADServe.** Buffered SSR works today via `.html(_:)`; streaming, live SSE,
and served runtime work as soon as the **`ADHTMLNIO` bridge** (RFC-0007 §3) forwards bytes — no ADServe
change required.

## 0. What already works (no ADServe change)

A handler can return rendered HTML **today**:

```swift
let bytes = try page.renderHydratable(arena: arena)        // ADHTML -> [UInt8]
return .raw(body: bytes, contentType: "text/html; charset=utf-8", status: .ok)
```

So server-rendered pages + the inline hydration state script already ship over the existing buffered
`ResponseContent`. The items below make it *first-class* (typed), *streamed*, *live*, and *served*.

## 1. `text/html` MediaType — P0, trivial

`ADServeCore.MediaType` has `json`/`jsonRaw`/`text`/`css`/… but no HTML. Add:

```swift
extension MediaType {
    public static let html = MediaType.custom("text/html; charset=utf-8")
}
// and a response convenience:
extension ResponseContent {
    public static func html(_ bytes: [UInt8], status: HTTPResponse.Status = .ok) -> ResponseContent {
        .raw(body: bytes, contentType: MediaType.html.value, status: status)
    }
}
```

ADHTML then returns `.html(page.renderHydratable(arena: arena))`. Do this first; it is independent of
the rest.

## 2. Streaming response (a back-pressured byte sink) — P1

Today `ResponseContent` is always fully buffered (`.raw(body: [UInt8], …)`). ADHTML's streaming
renderer (`AsyncForEach` + an `AsyncHTMLByteSink`, RFC-0002) needs to **write chunks as it renders** —
flush `<head>` immediately, stream read-model rows without materializing the whole page. Add a
streaming variant whose body sink matches ADHTML's `AsyncHTMLByteSink`:

```swift
// ADServe: the host-owned writer, backed by NIOAsyncChannelOutboundWriter (back-pressure is implicit
// in the async write — it suspends when the channel isn't writable).
public protocol ResponseStreamWriter: Sendable {
    mutating func write(_ bytes: ArraySlice<UInt8>) async throws   // matches ADHTML.AsyncHTMLByteSink
    mutating func flush() async throws
}

public enum ResponseContent {
    // …existing cases…
    case stream(
        contentType: String,
        status: HTTPResponse.Status = .ok,
        headers: HTTPFields = [:],
        body: @Sendable (_ writer: inout any ResponseStreamWriter) async throws -> Void)
}
```

Requirements: honor back-pressure (suspend on un-writable channel); keep the configurable body cap for
streamed bodies; ride the existing envelope (security headers, request-id); flush `<head>` before the
body completes. `ADHTMLNIO` (gated `ADHTML_NIO`) adapts `ResponseStreamWriter` ⇄ `AsyncHTMLByteSink`
(both are `write(_ ArraySlice<UInt8>) async throws`), drawing buffers from `ADFCore.ByteBufferPool`.

## 3. Server-Sent Events — P1

For live island updates (RFC-0003 §5): the server pushes `event: morph` (an HTML fragment to morph by
`id`) and `event: patch` (a JSON Merge Patch over the cell graph). A long-lived `text/event-stream`
response:

```swift
public protocol SSEWriter: Sendable {
    mutating func send(event: String?, data: String, id: String?, retry: Int?) async throws
    mutating func comment(_ text: String) async throws        // ": keep-alive" heartbeat
}

extension ResponseContent {
    case sse(headers: HTTPFields = [:], body: @Sendable (_ writer: inout any SSEWriter) async throws -> Void)
}
```

Requirements: keep the connection open and unbuffered; frame `event:`/`data:`/`id:`/`retry:` per the
HTML spec (split multi-line `data`); send periodic heartbeat comments; **honor client disconnect /
`Task` cancellation** (stop the source, free the slot); enforce a max-concurrent-SSE limit; emit
`Cache-Control: no-store`. The event source is the app's change feed (RFC-0008) — not a DB dependency
in the engine. ADHTML serializes patches via `ADJSONCore.JSONMergePatch`; ADServe just frames + writes.

## 4. Guarded static-asset serving — P1

The client runtime (`adh-runtime.min.js`, ADR-0006) and CSS/SVG assets must be served. ADServe has no
static handler today, but already ships the pieces: `pathHasTraversal(_:)`, `sha256HexLower(_:)` (for
ETag), `CachePolicy` + `If-None-Match`/304 handling.

```swift
// A guarded static handler (host-owned). ADHTML supplies the runtime bytes + their SRI hash.
public func staticAsset(root: String, cache: CachePolicy = .immutable) -> /* route */
```

Requirements: reject path traversal (reuse `pathHasTraversal`); content-type by extension
(`application/javascript` for `.js`, `text/css`, `image/svg+xml`); strong ETag (`sha256HexLower`) +
`Cache-Control` + `If-None-Match` → 304 (ADServe already has this); enforce a root jail. The runtime is
served with **Subresource Integrity** (`<script integrity="sha256-…">`) — ADServe just serves the
bytes; ADHTML/`ADHTMLSRI` computes the hash (swift-crypto, ADR-0011). Nice-to-have: precompressed
`.br`/`.gz` variants by `Accept-Encoding`.

## 5. Async handler path — P1 (enables #2/#3)

The matched route's `run` is **synchronous** today (`@Sendable (HandlerInput) throws ->
ResponseContent`). Streaming (#2) and SSE (#3) are inherently async (await the sequence; back-pressured
writes). The route may still *resolve* synchronously to a `.stream`/`.sse` `ResponseContent` whose
**body closure is async** and is driven by the engine on the NIO event loop — i.e. the async lives in
the response body, not necessarily the route resolver. Confirm this shape against ADServe's in-flight
middleware/async refactor so the seam tracks the settled API.

## 6. Per-request CSP nonce — P1, small

ADHTML emits an **inline** `<script type="application/adh-state+json">` (the state graph) and loads the
runtime. Under a strict `Content-Security-Policy`, inline scripts need a per-request **nonce** (or a
hash). ADServe's `SecurityHeaders` should support a per-request nonce: mint it, expose it on
`RequestStorage` so the handler stamps it on the `<script nonce=…>` (and on the runtime `<script>`),
and emit it in the `script-src 'nonce-…'` CSP header. Without this, a strict CSP blocks hydration.
(The state block is also `scriptJSON`-escaped by ADHTML — ADR-0003 — so it can't break out regardless.)

## What ADHTML does NOT need from ADServe

To scope the work: **no** template engine, **no** view layer or HTML knowledge in the engine, **no**
DB/ORM coupling, **no** WebSockets (SSE suffices for server→client; htmx/forms cover client→server).
ADServe stays persistence- and view-agnostic; it gains *transport* primitives only.

## Feature → capability map

| ADHTML feature | Needs ADServe… |
| --- | --- |
| Server-rendered pages/fragments (buffered) | #1 (or works today via `.raw`) |
| Streaming SSR / `AsyncForEach` rows / early `<head>` flush | #2 + #5 |
| Live island updates (morph + signal patch) | #3 + #5 |
| Shipping the client runtime + assets | #4 |
| Hydration under a strict CSP | #6 |

## Sequencing

1. **#1** now (trivial, unblocks typed buffered SSR).
2. **#2 + #5** together (streaming + async body) — the core of the streaming stack.
3. **#3** (SSE) — builds on #2/#5.
4. **#4** (static assets) — independent; can land any time alongside.
5. **#6** (CSP nonce) — with the first real page that ships the runtime.

All of this is the **ADServe-side** of ADR-0012 / spare-parts ADR-0046. The ADHTML-side bridge lives in
the gated `ADHTMLNIO` target and is written against this contract once it lands. Coordinate with the
in-flight ADServe middleware/async refactor.

## Verification (per capability)

- #1: a handler returns `.html(bytes)`; response is `text/html; charset=utf-8`.
- #2: a streamed page flushes `<head>` before the body finishes (observe first-byte timing); peak
  memory stays ~flat for a 100k-row list (probe).
- #3: an SSE stream delivers a `morph` and a `patch`; the connection survives a client reconnect and is
  torn down on disconnect; the slot is freed.
- #4: the runtime is served with a correct content-type + ETag/304; a traversal path is rejected; the
  SRI hash matches.
- #6: with a strict CSP, the inline state script + runtime load (nonce matches); without the nonce they
  are blocked (negative test).
