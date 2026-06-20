import ADHTML
import Benchmark

// A reactive component for the hydration benchmark (exercises @State -> stateCell + wire serialization).
@Component
struct BenchCounter {
    @State var count = 0

    var body: some HTML {
        Island("c", scope: [countSignal.id]) {
            button { "+" }.on("click", Behavior.increment(countSignal))
            span { String(count) }.bind(.text, to: countSignal.id)
        }
    }
}

// A realistic small page (the "usable in the targeted context" shape): document + nav + main + form.
func documentPage() -> some HTML {
    html {
        head {
            title { "ADHTML" }
            meta().attribute("charset", "utf-8")
            meta().name("viewport").content("width=device-width")
        }
        body {
            nav { ul { _HTMLArray((0 ..< 5).map { i in li { "item \(i)" } }) } }
            main {
                h1 { "Welcome" }
                section {
                    p { "Lorem ipsum dolor sit amet." }
                    p { "Consectetur adipiscing elit." }
                }
                form {
                    input().type("text").name("q").placeholder("Search")
                    button { "Go" }.type("submit")
                }
            }
        }
    }
}

// The ordo-one/benchmark suite (ADHTML_DEV-gated). Run: `ADHTML_DEV=1 swift package benchmark`.
// Measures the render path — build → lower → escape → emit — with p50/p90/p99 wall-clock, throughput,
// CPU, and malloc/peak-memory. `mallocCountTotal` is the key allocation-efficiency signal. The
// `*-prebuilt` case renders a pre-constructed view (engine only); the gap vs the build-each-iteration
// case is the cost of constructing the element tree from data (ARC/allocation), not the renderer.
nonisolated(unsafe) let benchmarks = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .throughput, .cpuTotal, .mallocCountTotal, .peakMemoryResident])

    Benchmark("render/small-fragment") { bm in
        for _ in bm.scaledIterations {
            blackHole(
                div {
                    "Hello, "
                    span { "world" }.class("name")
                }
                .class("greeting").render())
        }
    }

    Benchmark("render/wide-list-1k") { bm in
        let rows = (0 ..< 1000).map { "row \($0)" }
        for _ in bm.scaledIterations {
            blackHole(div { _HTMLArray(rows.map { row in p { row } }) }.render())
        }
    }

    Benchmark("escape/text-heavy") { bm in
        let payload = String(repeating: #"a<b>&"c'd "#, count: 256)
        for _ in bm.scaledIterations {
            blackHole(span { payload }.render())
        }
    }

    // Exposes the Copy-on-Write tax: each chained modifier copies the attribute store today.
    Benchmark("render/modifier-chain") { bm in
        for _ in bm.scaledIterations {
            blackHole(
                div { "x" }
                    .class("a").id("b").title("t").lang("en").dir("ltr").role("main")
                    .render())
        }
    }

    // Exposes reactive overhead: @State key allocation + island wire serialization.
    Benchmark("render/reactive-island") { bm in
        for _ in bm.scaledIterations {
            let arena = CellArena()
            blackHole(try? BenchCounter().renderHydratable(arena: arena))
        }
    }

    // A realistic page (server path: renderBytes, no String round-trip) — the headline "usable" metric.
    Benchmark("render/document") { bm in
        for _ in bm.scaledIterations {
            blackHole(documentPage().renderBytes())
        }
    }

    // Engine only: a PRE-built 1k view rendered each iteration. The gap vs render/wide-list-1k (which
    // rebuilds the tree from data every time) is the view-construction cost (ARC), not the renderer.
    Benchmark("render/wide-list-1k-prebuilt") { bm in
        let rows = (0 ..< 1000).map { "row \($0)" }
        let view = div { _HTMLArray(rows.map { row in p { row } }) }
        for _ in bm.scaledIterations {
            blackHole(view.renderBytes())
        }
    }

    // Scale: build + render 10k elements (server path).
    Benchmark("render/wide-list-10k") { bm in
        let rows = (0 ..< 10_000).map { "row \($0)" }
        for _ in bm.scaledIterations {
            blackHole(div { _HTMLArray(rows.map { row in p { row } }) }.renderBytes())
        }
    }

    // Sparse-escapable prose: exercises the SWAR fast-forward over long safe runs — the complement of
    // escape/text-heavy (dense). Splitting the two surfaces a regression on either path independently.
    Benchmark("escape/prose") { bm in
        let prose = String(repeating: "The quick brown fox & the lazy dog jumped over 5 logs. ", count: 64)
        for _ in bm.scaledIterations {
            blackHole(span { prose }.render())
        }
    }

    // The RFC-0019 Action DSL lowering: a fully-modified action → its `data-adh-*` attribute set.
    Benchmark("render/action-lowering") { bm in
        for _ in bm.scaledIterations {
            blackHole(
                input().attribute("name", "q")
                    .action(
                        .get("/rows").trigger(.input).debounce(.milliseconds(200)).include("q")
                            .target("rows").swap(.morph)
                    )
                    .render())
        }
    }

    // Wire-serialization scaling: 100 reactive islands → 100 cells filtered + scriptJSON-escaped. Isolates
    // the per-island wire cost (vs render/reactive-island's single island) as the island count grows.
    Benchmark("render/reactive-islands-100") { bm in
        for _ in bm.scaledIterations {
            let arena = CellArena()
            blackHole(try? div { _HTMLArray((0 ..< 100).map { _ in BenchCounter() }) }.renderHydratable(arena: arena))
        }
    }
}
