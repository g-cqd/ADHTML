// A lightweight, network-free release perf probe over ADHTMLCore — for quick local before/after
// measurement of the render/escape/reactive hot paths. The ordo-one suite (Benchmarks/ADHTMLSuite)
// remains the CI gate (with mallocCountTotal); this probe needs no DEV dependencies (no swift-syntax,
// no benchmark plugin), so it builds and runs offline. Run RELEASE:
//
//     swift run -c release ADHTMLPerfProbe
//
// It warms up, times each path over many iterations across several runs, and prints min + median
// ns/op. A global checksum (printed at the end) defeats dead-code elimination.

import ADHTMLCore

/// Accumulates a byte count from every measured render so the optimizer cannot elide the work.
/// `nonisolated(unsafe)`: a single-threaded probe (same pattern as the ordo-one suite's entry point).
nonisolated(unsafe) var checksum = 0

/// Time `body` over `iterations` per run, `runs` runs; report min + median ns/op.
@inline(never)
func measure(_ name: String, iterations: Int, runs: Int = 7, _ body: () -> Int) {
    for _ in 0 ..< 2000 { checksum &+= body() }  // warm up code + caches

    var perOp: [Double] = []
    perOp.reserveCapacity(runs)
    let clock = ContinuousClock()
    for _ in 0 ..< runs {
        var local = 0
        let start = clock.now
        for _ in 0 ..< iterations { local &+= body() }
        let elapsed = clock.now - start
        checksum &+= local
        let nanos = Double(elapsed.components.seconds) * 1e9 + Double(elapsed.components.attoseconds) / 1e9
        perOp.append(nanos / Double(iterations))
    }
    perOp.sort()
    let best = Int(perOp[0].rounded())
    let median = Int(perOp[perOp.count / 2].rounded())
    var label = name
    while label.count < 26 { label += " " }
    print("\(label) min \(best) ns   median \(median) ns/op")
}

// A reactive component for the hydration path (hand-written @State shape — no macro, so the probe
// avoids the swift-syntax dependency).
struct ProbeCounter: Component {
    var count: Int = 0
    var countSignal: Signal<Int> { ADHTMLRenderContext.state(key: "count", default: count) }

    var body: some HTML {
        Island("c", scope: [countSignal.id]) {
            button { "+" }.on("click", Behavior.increment(countSignal))
            span { String(count) }.bind(.text, to: countSignal.id)
        }
    }
}

// Lower a view to its opcode program (for the lower-vs-emit phase breakdown).
func lower<V: HTML>(_ view: V) -> HTMLProgram {
    var program = HTMLProgram()
    V._render(view, into: &program)
    return program
}

// A realistic small document (head + nav + main + form) for the document-render fixture.
func documentFixture() -> some HTML {
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

let rows = (0 ..< 1000).map { "row \($0)" }
let rows10k = (0 ..< 10_000).map { "row \($0)" }
let escapePayload = String(repeating: #"a<b>&"c'd "#, count: 256)  // pathologically escape-dense (~50%)
let prosePayload = String(  // realistic prose: a couple of escapables per ~60 safe chars (~5%)
    repeating: "The quick brown fox & the lazy dog jumped over <the> fence. ", count: 64)

print("ADHTMLPerfProbe (release) — hot-path ns/op")

measure("render/small-fragment", iterations: 200_000) {
    div {
        "Hello, "
        span { "world" }.class("name")
    }
    .class("greeting").render().utf8.count
}

measure("render/modifier-chain", iterations: 200_000) {
    div { "x" }
        .class("a").id("b").title("t").lang("en").dir("ltr").role("main")
        .render().utf8.count
}

measure("escape/text-heavy", iterations: 50_000) {
    span { escapePayload }.render().utf8.count
}

measure("escape/prose", iterations: 50_000) {
    span { prosePayload }.render().utf8.count
}

measure("render/wide-list-1k", iterations: 2_000) {
    div { _HTMLArray(rows.map { row in p { row } }) }.render().utf8.count
}

measure("render/reactive-island", iterations: 50_000) {
    (try? ProbeCounter().renderHydratable(arena: CellArena()))?.count ?? 0
}

// --- Larger / varied fixtures (scale + shape) ---

measure("render/wide-list-10k", iterations: 300) {
    div { _HTMLArray(rows10k.map { row in p { row } }) }.render().utf8.count
}

measure("render/attr-heavy-2k", iterations: 1_000) {
    div {
        _HTMLArray(
            (0 ..< 2_000)
                .map { i in
                    span { "x" }
                        .class("col").id("c\(i)").title("t").lang("en").dir("ltr").role("cell")
                        .data("row", "1").data("kind", "num")
                })
    }
    .render().utf8.count
}

measure("render/table-50x40", iterations: 1_000) {
    table {
        _HTMLArray(
            (0 ..< 50)
                .map { r in
                    tr { _HTMLArray((0 ..< 40).map { c in td { "\(r):\(c)" } }) }
                })
    }
    .render().utf8.count
}

measure("render/document", iterations: 20_000) {
    documentFixture().render().utf8.count
}

measure("render/reactive-100-islands", iterations: 1_000) {
    let arena = CellArena()
    let view = div { _HTMLArray((0 ..< 100).map { _ in ProbeCounter() }) }
    return (try? view.renderHydratable(arena: arena))?.count ?? 0
}

// --- Phase breakdown for the wide list: lowering (build program) vs emitting (program -> bytes) ---

let wideView = div { _HTMLArray(rows10k.map { row in p { row } }) }
let wide10kProgram = lower(wideView)

measure("phase/lower-10k", iterations: 300) { lower(wideView).ops.count }
measure("phase/emit-10k", iterations: 300) {
    var sink = ArraySink(reservingCapacity: wide10kProgram.ops.count * 16)
    Renderer.render(wide10kProgram, into: &sink)
    return sink.bytes.count
}

print("checksum: \(checksum)")
