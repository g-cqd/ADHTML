# ADR 0012 — ADServe integration & the streaming dependency

- **Status**: Proposed
- **Date**: 2026-06-19
- **Related**: RFC-0001, RFC-0002, RFC-0003; spare-parts-app ADR-0046 (ADServe view support); ADR-0010 (gating), ADR-0011 (reuse)

## Context

ADHTML renders bytes; ADServe serves them. Today ADServe returns fully-buffered
`ResponseContent.raw(body: [UInt8], contentType:, status:)`, has **no** `text/html` `MediaType`, no
streaming response, no Server-Sent Events, and no static-asset serving. The reactive/hydration stack
wants all four (spare-parts-app ADR-0046 specifies them as first-party ADServe work). ADServe is also
mid-refactor (it just gained a middleware layer).

## Decision

Integrate behind a small seam, **sequenced behind ADServe ADR-0046**:

- **Today (buffered)**: `ADHTML` renders to `[UInt8]` and returns
  `.raw(body:, contentType: "text/html; charset=utf-8", status:)`. Fully usable now; the core has **no**
  ADServe dependency.
- **When ADR-0046 lands (gated `ADHTMLNIO`)**: an `AsyncHTMLByteSink` over NIO `ByteBuffer`
  (`ADFCore.ByteBufferPool`, channel-writability back-pressure) for streaming render (flush `<head>`
  early — TTFB); an SSE responder for `event: morph`/`patch` (RFC-0003); the runtime served via
  ADServe's guarded static handler (reusing `pathHasTraversal`, ETag, `Cache-Control`, SRI).
- Add a `text/html` `MediaType` to ADServe (trivial; do first) and, optionally, a `ViewRenderer`-style
  port so the HTML adapter is swappable (parity with spare-parts ADR-0044's port).

## Consequences

- **Positive**: ADHTML ships value immediately via the buffered path; the streaming/SSE/asset
  capabilities slot in without touching the core (gated `ADHTMLNIO`); persistence-agnostic (views pull
  from the app, not a DB in the engine).
- **Negative**: the full stack depends on ADServe ADR-0046, which is proposed-not-built — a sequencing
  risk, mitigated by the buffered fallback and by `ADHTMLNIO` being gated. Coordinate with the in-flight
  ADServe middleware/async refactor so the bridge tracks the settled API.
- **Security**: new surface (static traversal, SSE connection limits, streamed-body caps) is
  threat-modeled with ADServe's security baseline; SSE/asset handlers enforce `can()` where scoped.
