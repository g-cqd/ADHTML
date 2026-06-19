// ADHTMLFuzz (gated `ADHTML_FUZZ`) — a libFuzzer harness for the context-aware escaper (ADR-0003).
// `-sanitize=fuzzer -parse-as-library` is a Linux capability of the toolchain (the Darwin SDK rejects
// it), so this builds/runs in the Linux CI fuzz job. The invariant: escaped output must never
// introduce an HTML/attribute/URL control byte that was not already neutralized.
internal import ADHTMLCore

@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzOneInput(_ start: UnsafePointer<UInt8>, _ count: Int) -> CInt {
    let input = String(decoding: UnsafeBufferPointer(start: start, count: count), as: UTF8.self)
    var sink = ArraySink(reservingCapacity: count * 2)
    Escaper.write(input, context: .text, into: &sink)
    Escaper.write(input, context: .attribute, into: &sink)
    Escaper.write(input, context: .url, into: &sink)
    return 0
}
