import ADHTML
import Benchmark

// The ordo-one/benchmark suite (ADHTML_DEV-gated). Run: `ADHTML_DEV=1 swift package benchmark`.
// Measures the render path — build → lower → escape → emit — across a small fragment, a wide list, and
// an escape-heavy payload, with p50/p90/p99 wall-clock, throughput, CPU, and malloc/peak-memory.
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
            blackHole(div { _HTMLArray(rows.map { p { $0 } }) }.render())
        }
    }

    Benchmark("escape/text-heavy") { bm in
        let payload = String(repeating: #"a<b>&"c'd "#, count: 256)
        for _ in bm.scaledIterations {
            blackHole(span { payload }.render())
        }
    }
}
