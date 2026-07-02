# Contributing to ADHTML

Developer tooling lives in the package itself — SwiftPM plugins and committed git hooks — so there
are no shell scripts to run and nothing to install globally. ADHTML is **RFC/ADR-first**: a
non-trivial change starts with (or updates) a document under [`docs/`](docs/README.md), then lands as
code in small, one-concern commits.

## Local dependency resolution

ADHTML depends on sibling `AD*` packages — `ADFoundation` (ADFCore) and `ADJSON` (ADJSONCore, the wire
serializer), with `ADServe` added when the NIO bridge lands. Each resolves from a local checkout when
its `<DEP>_PATH` env var is set, else from `github.com/g-cqd`. With the siblings checked out next to
this repo:

```sh
export ADFOUNDATION_PATH=../ADFoundation
export ADJSON_PATH=../ADJSON
```

## One-time setup

Enable the repo's git hooks (pre-commit lint, pre-push test), if present:

```sh
git config core.hooksPath .githooks
```

The toolchain's bundled `swift format` powers the plugins; no extra tools needed.

## Build system & toolchain

**Build with `--build-system native`.** ADHTML has a `.macro` target (`ADHTMLMacros`). The newer
default `swiftbuild` engine on the current Xcode-beta toolchain mislinks the macro module into
dependent test bundles (`swift test` fails to link with undefined `SwiftSyntax` symbols) — a
SwiftPM/toolchain bug, not an ADHTML one. The classic **`native`** build system handles macros
correctly, so all `swift build` / `swift test` / `swift package` commands take `--build-system native`
(CI does too). Drop the flag once the swiftbuild macro/test-link bug is fixed (ADR-0008).

**After changing parameter ownership (`borrowing` ↔ `consuming`), do a clean build** (`swift package
clean`). That changes the calling convention (an ABI change), and an *incremental* build can leave the
macro test bundle linked against the old convention — it crashes at runtime (SIGTRAP/SIGSEGV) rather
than failing to compile. CI builds clean, so this only bites incremental local runs (ADR-0013).

The toolchain is pinned to **Swift 6.4** via [`.swift-version`](.swift-version). swiftly users can run
`swiftly install 6.4 && swiftly use 6.4` to manage it; otherwise select an Xcode whose Swift is 6.4.

## Everyday commands

```sh
swift build --build-system native                          # build (see "Build system" above)
swift test  --build-system native                          # run the test suite
swift test  --build-system native --enable-code-coverage

swift package format        # format in place (add --allow-writing-to-package-directory if prompted)
swift package lint          # formatting gate + shipped-library discipline (what CI runs)
```

`swift package lint` is the single source of truth for lint: a `swift format lint --strict` pass over
the package plus shipped-library discipline on `Sources/ADHTML` **and** `Sources/ADHTMLCore`
(force-unwrap / force-cast / force-try ban via swift-format AST rules, plus the `.adbuildtools.json`
discipline flags). Annotate a reviewed exception with `// swift-format-ignore: NeverForceUnwrap` on
the line above it.

## Escaping & XSS (the security-critical surface)

Output encoding is **escape-by-default and context-aware** (ADR-0003). The only unescaped path is
`RawHTML(unsafelyEscaped:)` — grep for it to enumerate every bypass in review. New escaping logic
ships with golden tests and an entry in `Tests/ADHTMLXSSTests` (OWASP XSS vectors must render inert).

## Sanitizers

`--sanitize` instruments the whole graph (no manifest change). TSan and ASan are **mutually
exclusive**, so run them as separate passes:

```sh
swift test --sanitize=thread                        # data races
swift test --sanitize=address --sanitize=undefined  # OOB / use-after-free in the byte paths
```

## Coverage-guided fuzzing (libFuzzer)

The `ADHTMLFuzz` target drives the escaper and (later) the wire (de)serializer from one entry point.
It is gated behind `ADHTML_FUZZ` and built with `-sanitize=fuzzer -parse-as-library`, a **Linux**
capability of the Swift toolchain (the Darwin SDK rejects the flag):

```sh
ADHTML_FUZZ=1 swift build --product ADHTMLFuzz
"$(ADHTML_FUZZ=1 swift build --product ADHTMLFuzz --show-bin-path)/ADHTMLFuzz" corpus -max_total_time=300
```

A crash writes a `crash-*` reproducer; commit it as a regression test under `Tests/`.

## Gating flags

Heavier or host-coupling dependencies are gated by environment variable so consumers never resolve
them:

```sh
ADHTML_DEV=1 swift build                       # build-time format enforcement (LintBuild plugin)
ADHTML_DEV=1 swift package generate-documentation --target ADHTMLCore --target ADHTML
ADHTML_DEV=1 swift package benchmark           # ordo-one/benchmark suite (Benchmarks/ADHTMLSuite)
ADHTML_SERVE=1 swift test --filter ADHTMLServeTests   # legacy alias: ADHTML_NIO
```

`ADHTML_MARKDOWN`, `ADHTML_SRI`, and `ADHTML_OBS` gate the swift-markdown, swift-crypto (SRI only),
and observability adapters respectively.

## Benchmarks & the regression baseline

```sh
ADHTML_DEV=1 swift package benchmark                         # full ordo-one/benchmark suite
```

Regression gating compares each run against a committed baseline under `.benchmarkBaselines/main`.
Hosted-runner timings differ from a local machine, so generate the baseline **on the CI runner**
(workflow dispatch with `update_baseline=true`), download the artifact, and commit it with
`git add -f .benchmarkBaselines/main` (local baselines are gitignored).

## Dependencies & `Package.resolved`

The shipped graph is deliberately thin: `ADHTMLCore` depends only on `ADFCore` (ADFoundation) and
`OrderedCollections` (swift-collections); the macro target adds swift-syntax. Everything heavier is
gated. `Package.resolved` is **gitignored** (the library convention — an application pins exact
versions; a library lets its consumers' resolution win).

## CI

A single workflow — `.github/workflows/ci.yml` — chains lint → build → test and fans out
(platforms, sanitizers, benchmarks, Linux, fuzz, docs) only after the gate passes. DocC is built
with `--warnings-as-errors` so a broken `<doc:>` link fails review.
