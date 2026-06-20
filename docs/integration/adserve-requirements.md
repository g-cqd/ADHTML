# What ADHTML needs from ADServe

- **Status**: Proposed (requirements)
- **Date**: 2026-06-20
- **Related**: ADHTML ADR-0012 (ADServe integration), ADR-0006 (client runtime), RFC-0003 (reactivity/hydration); spare-parts-app ADR-0046 (ADServe view & streaming support). Grounded in `ADServe/Sources/ADServeCore/ADServeCore.swift` + `HTTPServer.swift` + `Middleware.swift`.

This is the contract ADHTML needs the **host** (ADServe) to provide. ADHTML renders bytes and emits a
hydration wire format + a static client runtime; **ADServe transports them**. The split is deliberate
(ADR-0012): the engine stays persistence- and transport-agnostic; the host owns sockets, streaming,
SSE, and static files.

## TL;DR

| # | Capability | Why ADHTML needs it | ADServe today | Priority / effort |
| --- | --- | --- | --- | --- |
| 1 | `text/html` `MediaType` (+ `.html(_:)` convenience) | Serve rendered pages/fragments with the right content-type | **Missing** (`MediaType` has json/css/… not html) | **P0 / trivial** |
| 2 | Streaming response (back-pressured byte sink) | Flush `<head>`/early markup + stream `AsyncForEach` rows (TTFB; bounded memory) | **Missing** (every response is one buffered `[UInt8]`) | **P1 / medium** |
| 3 | Server-Sent Events (`text/event-stream`) | Push live `morph`/`patch` updates to islands (RFC-0003) | **Missing** | **P1 / medium** |
| 4 | Guarded static-asset serving | Serve the `adh-runtime.min.js` (+ CSS, SVGs) with ETag/Cache-Control/SRI | **Missing** (no static handler) | **P1 / medium** |
| 5 | Async handler path | #2 and #3 are inherently async (await the sequence; back-pressured writes) | Handler `run` is **sync** (`(HandlerInput) throws -> ResponseContent`) | **P1 / medium** |
| 6 | Per-request CSP nonce | Allow the inline `<script type="application/adh-state+json">` + the runtime under a strict CSP | `SecurityHeaders` exists; no per-request nonce | **P1 / small** |

P0 unblocks **buffered SSR today**; P1 unblocks the **streaming + live + interactive** stack. Until P1
lands, ADHTML works fully via buffered `.raw(text/html)` (just no streaming/SSE/served-runtime).

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
