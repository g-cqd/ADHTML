# ADHTML

A **reactive, hydratable, Swift-only server-side rendering engine** for the `AD*` family.

ADHTML renders type-safe HTML to bytes for a SwiftNIO server (ADServe) and — uniquely among Swift
HTML libraries — emits **hydration state plus a tiny client runtime**, so server-rendered markup
becomes interactive without a JavaScript framework. There are **no template files**: views,
components, and client behaviors are all `.swift`, so the *entire server scope type-checks and
compiles as one unit*. `swift build` is the template compiler.

> **Status: pre-1.0.** This repository currently contains the design corpus (4 RFCs + 12 ADRs under
> [`docs/`](docs/)) and a minimal **compiling render-core skeleton** (the iterative renderer +
> context-aware escaping). The reactivity/hydration subsystem, macros, and the NIO/Markdown/SRI
> adapters are specified in the docs and land in subsequent passes. See [`docs/README.md`](docs/README.md).

## Why

- **One constraint reshapes everything**: the SSR host is Swift (NIO), which cannot run JavaScript
  server-side. So ADHTML renders HTML *in Swift* and ships *state + a small generic runtime* for the
  client — never a second copy of your view logic. (Background: spare-parts-app **RFC-0018** /
  **ADR-0044**, which deferred this first-party engine until the reactive/hydratable requirement
  justified it. It does now.)
- **Type-checked end to end**: phantom-typed elements reject illegal element/attribute combinations at
  compile time; the client-behavior vocabulary is a closed Swift `enum`, so event→state bindings are
  statically checked. (RFC-0004 / ADR-0009.)
- **State of the art, most performant possible**: an **iterative (non-recursive)** renderer over a
  flat opcode program (bounded memory, no deep-input stack-overflow DoS), **escape-by-default**
  context-aware output encoding, and **resumable islands** (Astro topology × Qwik serialization ×
  fine-grained signals) over a **~2–6 KB hand-written JS runtime** — not Swift→WASM.

## Hello, world

```swift
import ADHTML

let markup = div {
    "Hello, "
    span { "world" }.class("name")
}
.class("greeting")
.render()
// <div class="greeting">Hello, <span class="name">world</span></div>
```

Text is **escaped by default** in the correct context; raw insertion is the single, greppable
`RawHTML(unsafelyEscaped:)` hatch.

## Architecture (one screen)

| Layer | Decision | Doc |
|---|---|---|
| Rendering | Iterative opcode renderer → `[UInt8]`/streaming; zero `any`, phantom-`Tag` elements | RFC-0002 · ADR-0002 |
| Escaping | Escape-by-default, context-aware (`text/attribute/url/css/scriptJSON`); URL allowlist | ADR-0003 |
| Reactivity | Serializable fine-grained signals (not `@Observable`); server-evaluated for SSR | ADR-0004 |
| Hydration | Opt-in **islands + resumable wiring** (reject full / whole-page hydration) | ADR-0005 |
| Wire format | Versioned, index-deduped JSON via ADJSON; SSE + JSON Merge Patch (RFC 7396) | ADR-0007 |
| Client runtime | One hand-written ~2–6 KB JS interpreter, SRI-hashed (reject Swift→WASM) | ADR-0006 |
| Swift-only | No template files; whole-scope compile-time type-checking | RFC-0004 · ADR-0009 |
| Packaging | Foundation-free `ADHTMLCore`; env-gated NIO/Markdown/SRI/Obs/Fuzz | ADR-0010 |

## Products

| Product | Role | Gate | Status |
|---|---|---|---|
| `ADHTMLCore` | Foundation-free render engine (DOM, iterative renderer, escaping) | — | skeleton |
| `ADHTML` | Umbrella: core + macros + conveniences | — | skeleton |
| `ADHTMLMacros` | `.macro` target (component/HTML-literal macros) | — | placeholder |
| `ADHTMLNIO` | NIO `ByteBuffer` byte-sink + ADServe bridge | `ADHTML_NIO` | planned |
| `ADHTMLMarkdown` | Markdown → ADHTML nodes (swift-markdown) | `ADHTML_MARKDOWN` | planned |
| `ADHTMLSRI` | Subresource-Integrity hashing of the client runtime (swift-crypto) | `ADHTML_SRI` | planned |
| `ADHTMLObservability` | Render-path logging/metrics/tracing | `ADHTML_OBS` | planned |
| `ADHTMLFuzz` | libFuzzer harness for the escaper/parser (Linux) | `ADHTML_FUZZ` | planned |

## Building locally

ADHTML depends on sibling `AD*` packages. Point SwiftPM at local checkouts via `<DEP>_PATH` (else it
resolves them from `github.com/g-cqd`):

```sh
export ADFOUNDATION_PATH=../ADFoundation
swift build
swift test
```

Deployment floor: macOS 15 / iOS 18 / tvOS 18 / watchOS 11 / visionOS 2 (pinned by stdlib
`Synchronization.Mutex`). `Span` is adopted (it back-deploys); `InlineArray`/`UTF8Span` are
deliberately not adopted (they would raise the floor to the 2025 SDKs).

## Gating environment variables

| Variable | Enables |
|---|---|
| `ADHTML_DEV` | Lint/format plugins, DocC, the ordo-one benchmark suite |
| `ADHTML_NIO` | `ADHTMLNIO` (swift-nio `ByteBuffer` sink + ADServe bridge) |
| `ADHTML_MARKDOWN` | `ADHTMLMarkdown` (swift-markdown) |
| `ADHTML_SRI` | `ADHTMLSRI` (swift-crypto SHA-256 for Subresource Integrity) |
| `ADHTML_OBS` | `ADHTMLObservability` (swift-log / swift-metrics / swift-distributed-tracing) |
| `ADHTML_FUZZ` | `ADHTMLFuzz` (libFuzzer; Linux only) |

Consumers of `ADHTML` / `ADHTMLCore` never resolve any gated dependency.

## Design corpus

The full research and decision record lives in [`docs/`](docs/README.md): **RFCs** (umbrella,
rendering core, reactivity/hydration/wire, whole-scope compile-time SSR) and **ADRs** (the discrete
decisions). Start with [RFC-0001](docs/rfcs/0001-adhtml-reactive-hydratable-ssr-engine.md).

## Relationship to the AD\* family

ADHTML is a sibling of `ADFoundation` (reuses `ADFCore`: `ByteBufferPool`, `XXH64`, `ASCII`,
`PercentCoding`), `ADJSON` (wire-state serialization + `JSONMergePatch`), and `ADServe` (the HTTP
host; reuses `sha256HexLower`/`pathHasTraversal`). It is the view layer that spare-parts-app
RFC-0018 / ADR-0044 / ADR-0046 sequence into the SSR/hypermedia stack.

## License

MIT © 2026 g-cqd. See [LICENSE](LICENSE).
