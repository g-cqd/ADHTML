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

// The ordo-one/benchmark suite (ADHTML_DEV-gated). Run: `ADHTML_DEV=1 swift package benchmark`.
// Measures the render path — build → lower → escape → emit — across a small fragment, a wide list, an
// escape-heavy payload, a modifier chain (the CoW tax), and a reactive island (state + wire), with
// p50/p90/p99 wall-clock, throughput, CPU, and malloc/peak-memory.
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
}
