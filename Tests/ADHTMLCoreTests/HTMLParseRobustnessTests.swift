// Robustness gate for the FULL HTML parse pipeline on untrusted input — tree construction
// (`HTMLNode.parse`) AND the recursive walks over the result (`markdown()`/`plainText()` in HTMLMarkdown,
// `first(where:)`/`firstElement`/all-descendants in HTMLExtract). `HTMLTapeRobustnessTests` already proves
// the byte-level TOKENIZER never reads out of bounds / crashes / hangs; this is the parallel gate one layer
// up, where the crawl actually consumes the tree. The load-bearing properties: (1) no input — random soup
// or adversarially deep — crashes or hangs the parse+walk; (2) the tree builder's nesting cap keeps the
// RECURSIVE walks bounded, so they survive a pathologically deep page on a small (worker) stack. Property
// (2) is the regression lock for the stack-overflow DoS fixed by the tree-depth cap.

import ADTestKit
import Testing

@testable import ADHTMLCore

struct HTMLParseRobustnessTests {
    /// A few distinct nesting SHAPES — the depth-overflow risk is not specific to `<div>`; any element that
    /// opens a frame compounds it (lists, quotes, sections), and mixed open/close exercises the builder's
    /// implied-close + nearest-match recovery at depth too.
    private static let deepShapes: [(open: String, close: String)] = [
        ("<div>", "</div>"),  // plain block nesting
        ("<ul><li>", "</li></ul>"),  // exercises implied-close + nearest-match recovery at depth
        ("<blockquote>", "</blockquote>")  // a distinct block path (markdown quote prefixing)
    ]

    @Test func parseAndWalkSurviveAdversarialDepthOnA512KiBStack() {
        // The crawl parses UNTRUSTED HTML on worker threads and the markdown/extract passes walk the tree by
        // RECURSION. The tree builder caps element nesting so those walks stay bounded — but the multi-MB main
        // test stack would MASK a regression. Pin to a 512 KiB worker stack (the AD-family recursive-descent
        // floor) and sweep depths straddling the builder's cap up to 1_500 — several × past the ~512-frame
        // depth at which these walks overflow a 512 KiB stack uncapped — across each shape. A missing or
        // too-large cap would SIGBUS on the deep shapes; reaching the end of the sweep proves the recursion
        // stays bounded. (Straddles 128, the tree builder's `maxDepth`.)
        DepthSweep.around([128], upTo: 1_500)
            .run { depth in
                for shape in HTMLParseRobustnessTests.deepShapes {
                    let html =
                        String(repeating: shape.open, count: depth) + "DEEP"
                        + String(repeating: shape.close, count: depth)
                    let tree = HTMLNode.parse(html)
                    _ = tree.first?.markdown()  // recursive
                    _ = tree.first?.plainText()  // recursive
                    _ = tree.first?.first(where: { _ in false })  // recursive query, forced full traversal
                }
            }
    }

    @Test func fullParsePipelineNeverCrashesOnRandomInput() {
        // Extends HTMLTapeRobustnessTests' discipline through the tree builder AND the recursive walks — the
        // tape-only fuzz can't reach them (it stops at `materialize()`), which is exactly why a deep-nesting
        // overflow slipped through. Random metacharacter soup + random (un)balanced tag streams; any
        // crash / OOB / hang fails, and the seed makes a failure replay deterministically.
        var rng = SeededRNG(seed: 0x4D5A_B0DE_F00D)
        let meta: [Character] = [
            "<", ">", "/", "=", "\"", "'", "&", ";", "#", "-", "x", "p", "a", " ", "\n", "é"
        ]
        let tags = ["p", "div", "span", "ul", "li", "a", "h2", "pre", "code", "blockquote", "br", "img"]

        for _ in 0 ..< 600 {
            var html = ""
            if rng.bool() {  // metacharacter soup — partial tags, stray entities, unbalanced quotes
                for _ in 0 ..< rng.int(in: 1 ... 300) { html.append(rng.pick(meta)) }
            } else {  // random (un)balanced tag stream — may nest, may dangle a stray end tag
                for _ in 0 ..< rng.int(in: 1 ... 80) {
                    let tag = rng.pick(tags)
                    html += rng.bool() ? "<\(tag)>" : "</\(tag)>"
                    if rng.bool() { html += "txt" }
                }
            }
            let tree = HTMLNode.parse(html)
            for node in tree {  // the recursive walks must terminate without trapping on ANY of this
                _ = node.markdown()
                _ = node.plainText()
                _ = node.first(where: { _ in false })
            }
        }
    }

    @Test func adjacentTextCoalescingIsLinearNotQuadratic() {
        // An adversarial run of text tokens separated by NO-NODE tokens: `a</z>` repeated. Each `</z>`
        // matches no open element (ignored, appends nothing), so the `a` runs stay adjacent siblings the
        // builder coalesces. The old `.text(prev + value)` coalescing reallocated the whole growing
        // accumulator per token → O(n²): N=200_000 (~1 MB) took tens of seconds — a remote CPU-DoS on the
        // untrusted crawl input. The pending-text accumulator makes accumulation amortized O(1) / O(n) total.
        // Two locks: (1) correctness — the whole run collapses to ONE `.text` node of N 'a's (coalescing
        // across stray end tags preserved); (2) linearity — it finishes far under a budget the quadratic
        // would exceed by orders of magnitude (linear ≈ a few ms; quadratic ≈ tens of seconds).
        let n = 200_000
        let html = String(repeating: "a</z>", count: n)
        var tree: [HTMLNode] = []
        let elapsed = ContinuousClock().measure { tree = HTMLNode.parse(html) }
        #expect(tree.count == 1)
        if case .text(let coalesced) = tree.first {
            #expect(coalesced.count == n)  // all N 'a's coalesced into a single node
        } else {
            Issue.record("expected a single coalesced .text root, got \(tree.count) node(s)")
        }
        #expect(elapsed < .seconds(3), "tree-build text coalescing looks quadratic again: \(elapsed) for N=\(n)")
    }
}
