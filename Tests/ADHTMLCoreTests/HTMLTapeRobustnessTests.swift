// Robustness gate for the byte-level tape tokenizer. HTMLTape scans raw bytes through an
// UnsafePointer, so the load-bearing safety property is: NO input — malformed, truncated, or random
// — may read out of bounds, crash, or hang. These tests feed it hostile fragments and seeded random
// byte soup; a crash/OOB aborts the test process (= failure) and a hang trips the timeout. Output
// correctness on well-formed input is gated by HTMLTapeTests' differential check; here any non-crash
// result is acceptable.

import ADTestKit
import Testing

@testable import ADHTMLCore

struct HTMLTapeRobustnessTests {
    @Test(arguments: [
        "", " ", "\n", "\t\r\n",
        "<", ">", "<<", ">>", "<<>>", "<>", "< >", "<\t>",
        "<a", "<a ", "<a b", "<a data-b=", "<a b=c", "<a b=\"x", "<a b='x", "<br /", "<a b c d e",
        "<a href=", "<a href=>", "<a =x>", "<a b==c>", "<a \"\"='x'>",
        "<!--", "<!-- x", "<!--->", "<!----", "<!-->", "<!", "<!x", "<!DOCTYPE", "<!DOCTYPE html",
        "<script>x", "<style>y", "<title>z", "<script>a</scrip", "<SCRIPT>x</SCRIPT>",
        "<textarea>&amp;", "<xmp><b></xmp>",
        "&", "&#", "&#x", "&#;", "&#x;", "&#xZZ;", "&#99999999999;", "&#xFFFFFFFF;",
        "&notreal;", "&;", "&amp", "&#65", "&#x41", "a&amp&lt;b", "&&&;;;",
        "</>", "</ >", "</123>", "</p", "</p ", "</p attr=x>", "</>x",
        "<123>", "<-x>", "< data-a>", "<p/></p>", "<p><b>x</p></b>",
        "<![CDATA[x]]>", "<a href=<b>>", "<?xml version=\"1.0\"?>",
        "café <p>résumé — 日本語</p> 🎉", "<p title=\"é&amp;\">😀</p>",
        String(repeating: "<a><b><c>", count: 200) + "text",  // deep nesting / many tags
        String(repeating: "x", count: 5000),  // long text run (exercises the SWAR path)
        "<p>" + String(repeating: "&amp;", count: 1000) + "</p>"  // entity-dense
    ])
    func malformedInputNeverCrashes(_ html: String) {
        // Build + fully materialize; navigation must also terminate. A crash/OOB/hang here fails.
        let tape = HTMLTape.build(html)
        let tokens = tape.materialize()
        #expect(tokens.count >= 0)
        var index = 0
        var steps = 0
        while index < tape.slotCount, steps < tape.slotCount + 1 {
            index = tape.nextIndex(after: index)
            steps += 1
        }
        #expect(index >= tape.slotCount)  // navigation reached the end (no stall)
    }

    @Test func seededRandomByteSoupNeverCrashes() {
        // ADTestKit's deterministic SeededRNG over HTML-metacharacter-biased characters — partial
        // tags, stray entities, unbalanced quotes — the shapes a state machine is most likely to walk
        // off the end on. Reproducible: a failure replays from the same seed.
        var rng = SeededRNG(seed: 0xAD11_0FF5_E701)
        let alphabet: [Character] = [
            "<", ">", "/", "=", "\"", "'", "&", ";", "#", "!", "-", "x", "y", "a", "b", "p", " ",
            "\n", "1", "é"
        ]
        for _ in 0 ..< 400 {
            let length = rng.int(in: 1 ... 256)
            var html = ""
            html.reserveCapacity(length)
            for _ in 0 ..< length { html.append(rng.pick(alphabet)) }
            // Must not crash / read out of bounds / hang.
            _ = HTMLTape.build(html).materialize()
        }
    }
}
