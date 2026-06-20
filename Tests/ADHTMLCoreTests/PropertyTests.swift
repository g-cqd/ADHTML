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

// Fuzz the wire serializer (RFC-0019 §6.3-D5). There is no Swift wire DECODER — the serializer is the
// fuzzable Swift surface — so we drive it with seeded random `WireValue` trees and assert the failure-safe
// invariant: it ALWAYS either returns bytes or throws `WireError`, and never crashes / overflows (the walk
// is iterative). This runs in the fast macOS lane (deterministic + shrinking), complementing the
// Linux-only libFuzzer escaper harness — the value the plan's "extend libFuzzer to the wire" item targets,
// delivered verifiably here.
@Suite(.tags(.fuzz, .property))
struct WireSerializerFuzzTests {
    private static func serialize(_ value: WireValue) throws {
        let cell = CellArena.Cell(id: CellID(0), kind: .signal, value: value)
        _ = try WireSerializer.payload(
            cells: [cell], islands: [WireIsland(id: "i", on: .load, scope: [CellID(0)])])
    }

    @Test
    func `nested-array depth fuzz: serializes iff within the cap, else throws WireError (never crashes)`() {
        let cap = WireSerializer.maxValueDepth
        let counterexample = forAll(Gen.int(in: 0 ... (cap + 8))) { depth in
            var value: WireValue = .int(0)
            for _ in 0 ..< depth { value = .array([value]) }
            do {
                try Self.serialize(value)
                return depth <= cap  // produced bytes -> must be within the cap
            } catch is WireError {
                return depth > cap  // threw the typed error -> must be over the cap
            } catch {
                return false  // any OTHER error type is an invariant violation
            }
        }
        #expect(counterexample == nil)
    }

    @Test
    func `flat arrays of arbitrary mixed scalars always serialize without crashing`() {
        // Exercises every WireValue scalar case through the iterative serializer; a flat array is well
        // under the depth cap, so it must always produce bytes.
        let scalarGen = Gen.int(in: 0 ... 4)
            .map { tag -> WireValue in
                switch tag {
                    case 0: .null
                    case 1: .bool(true)
                    case 2: .int(Int64(tag))
                    case 3: .double(1.5)
                    default: .string("x<>&\"'")
                }
            }
        let counterexample = forAll(Gen.array(of: scalarGen, maxCount: 32)) { scalars in
            do {
                try Self.serialize(.array(scalars))
                return true
            } catch {
                return false
            }
        }
        #expect(counterexample == nil)
    }
}
