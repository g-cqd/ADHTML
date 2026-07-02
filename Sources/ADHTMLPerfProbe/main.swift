// TEMPORARY harness (restore with `git checkout -- Sources/ADHTMLPerfProbe/main.swift`).
import ADHTMLCore
import ADHTMLOracle

func same(_ name: String, _ html: String) -> Bool {
    let got = HTMLTape.build(html).materialize()
    let want = HTMLTokenizer.tokenize(html)
    if got == want { return true }
    print("FAIL \(name)\n  got:  \(got)\n  want: \(want)")
    return false
}

var ok = true
for (name, html) in [
    ("tags+attrs", "<a href=\"x\" class='y' disabled>text</a>"),
    ("entities", "Hello &amp; &lt;world&gt; &#65;&#x42;"),
    ("comment", "<!-- c -->"), ("doctype", "<!DOCTYPE html>"),
    ("script", "<script>if (a<b) x('</p>')</script>"),
    ("title", "<title>A &amp; B</title>"),
    ("longtext", String(repeating: "word ", count: 5000) + "&amp; <b>x</b>"),
    (
        "mixed",
        "<!DOCTYPE html><html lang=\"en\"><head><title>T &amp; U</title><meta charset='utf-8'></head>"
            + "<body class=\"main\" data-x><h1 id='x'>Hi &lt;there&gt; &#9731;</h1><p>line<br/>two</p>"
            + "<script>if(a<b){x('</p>')}</script><style>.c{color:red}</style><!-- n --><ul><li>a</li></ul>"
            + "</body></html>"
    )
] { ok = same(name, html) && ok }
print(ok ? "ORACLE: ALL PASS" : "ORACLE: FAILURES")

let clock = ContinuousClock()
func bestMs(_ runs: Int, _ body: () -> Int) -> Double {
    var best = Double.infinity
    for _ in 0 ..< runs {
        let s = clock.now
        _ = body()
        let e = clock.now - s
        best = min(best, Double(e.components.seconds) * 1000 + Double(e.components.attoseconds) / 1e15)
    }
    return best
}

let nodeDense = "<ul>" + String(repeating: "<li>x</li>", count: 250_000) + "</ul>"
let attrHeavy = String(
    repeating: "<div class=\"box\" id=\"n\" data-row=\"1\" data-kind=\"num\" role=\"cell\">y</div>", count: 100_000)
let prose = String(
    repeating: "<p>The quick brown fox &amp; the lazy dog jumped over the fence again and again.</p>", count: 80_000)
let realistic = String(
    repeating: "<article class=\"card\"><header><h2><a href=\"/x\">Title &mdash; sub</a></h2></header>"
        + "<p>Body text with <code>inline</code> and <em>emphasis</em> &amp; entities.</p>"
        + "<footer><time datetime=\"2026\">2026</time></footer></article>", count: 20_000)

func bench(_ name: String, _ html: String) {
    let bytes = html.utf8.count
    for _ in 0 ..< 3 { _ = HTMLTape.build(html).slotCount }
    let ms = bestMs(7) { HTMLTape.build(html).slotCount }
    var label = name
    while label.count < 12 { label += " " }
    print("\(label) \(bytes / 1024) KiB, best \(ms) ms = \(Double(bytes) / 1e6 / (ms / 1000)) MB/s")
}

print("BUILD throughput (tape):")
bench("node-dense", nodeDense)
bench("attr-heavy", attrHeavy)
bench("prose", prose)
bench("realistic", realistic)
