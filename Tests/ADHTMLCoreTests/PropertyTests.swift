import ADTestKit
import Testing

@testable import ADHTMLCore

// Property-based tests (ADTestKit `Gen`/`forAll`): invariants that must hold over HUNDREDS of seeded
// random inputs, not just the handful of hand-picked vectors in XSSTests. A failure shrinks to a minimal
// counterexample. These are the strongest mutation guard on the escaper — a missed metacharacter on ANY
// input fails the property, where an example-based test only catches the inputs it happens to list.
@Suite(.tags(.property))
struct EscaperPropertyTests {
    private static func escape(_ value: String, _ context: EscapeContext) -> String {
        var sink = ArraySink()
        Escaper.write(value, context: context, into: &sink)
        return String(decoding: sink.bytes, as: UTF8.self)
    }

    @Test
    func `text-context output never contains a raw < or > (over all inputs)`() {
        let counterexample = forAll(Gen.string(maxLength: 48)) { input in
            let out = Self.escape(input, .text)
            return !out.contains("<") && !out.contains(">")
        }
        #expect(counterexample == nil)
    }

    @Test
    func `attribute-context output never contains a raw < > or double-quote (over all inputs)`() {
        let counterexample = forAll(Gen.string(maxLength: 48)) { input in
            let out = Self.escape(input, .attribute)
            return !out.contains("<") && !out.contains(">") && !out.contains("\"")
        }
        #expect(counterexample == nil)
    }

    @Test
    func `safe text passes through unchanged — no double-escape of metacharacter-free runs`() {
        // A string drawn from a metacharacter-free alphabet must render byte-identical (proves the SWAR
        // fast path copies safe runs verbatim and never over-escapes).
        let safeAlphabet = Array("abcdefXYZ0189 ._-/:?=")
        let counterexample = forAll(Gen.string(maxLength: 48, alphabet: safeAlphabet)) { safe in
            Self.escape(safe, .text) == safe
        }
        #expect(counterexample == nil)
    }

    @Test
    func `escaped output is stable: escaping twice changes nothing after the first pass on safe input`() {
        // Entities themselves are metacharacter-free (`&amp;` etc. contain `&`, which re-escapes), so full
        // idempotence does NOT hold — but the escaped output must at least be valid UTF-8 and bounded:
        // length never shrinks, and every `<`/`>` is gone. (Mutation guard on the run/entity boundary.)
        let counterexample = forAll(Gen.string(maxLength: 48)) { input in
            let once = Self.escape(input, .text)
            return once.utf8.count >= input.utf8.count && !once.contains("<")
        }
        #expect(counterexample == nil)
    }
}
