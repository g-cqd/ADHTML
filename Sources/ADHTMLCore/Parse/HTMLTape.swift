// HTMLTape — the high-performance byte-level HTML tokenizer. Where `HTMLTokenizer` is the
// correctness-first reference (a `[Unicode.Scalar]` state machine emitting `[HTMLToken]` with a
// String per token), this scans the raw UTF-8 bytes ONCE and records a flat preorder tape of
// `UInt64` slots holding zero-copy (offset, length) ranges into the source — no per-token String,
// no scalar expansion. It is modeled on ADJSON's tape parser and built on the family's shared
// kernels: `ADFCore.TapeSlot` (the slot bit-packing, promoted from ADJSON), `ADFCore.ASCII`
// (classification), and `ADFCore.SWAR` (the word-at-a-time stop-mask used to find the next `<`).
//
// `materialize()` reconstructs `[HTMLToken]` (lazily decoding entities + lowercasing names) so the
// same correctness oracle proves both paths; tree construction will instead walk the tape directly,
// touching the cold side-arrays only for the start tags it needs.
//
// The scanner is a value type (ADJSON's `TapeBuilder` shape): the input `[UInt8]` plus growable
// arrays, mutating methods — no closure-capture boxing on the hot path, and no raw pointers, so the
// strict-memory-safety surface (SE-0458) stays empty. Byte reads are scalar, not SWAR: node-dense
// markup has short text runs where an 8-byte stride is pure overhead (~25× the reference tokenizer
// on a node-dense fixture; ~0.57 GB/s).

import ADFCore

// MARK: - Slot kinds (the 4-bit TapeSlot tag)

private enum HTMLTapeKind {
    static let text: UInt8 = 0  // aux = (length << 1) | needsDecode,  low = byte offset
    static let startTag: UInt8 = 1  // low = index into `starts` (name + attrs + selfClosing live there)
    static let endTag: UInt8 = 2  // aux = length << 1,  low = byte offset of the tag name
    static let comment: UInt8 = 3  // aux = length << 1,  low = byte offset of the comment body
    static let doctype: UInt8 = 4  // aux = length << 1,  low = byte offset of the name
    static let doctypeNil: UInt8 = 5  // a DOCTYPE with no name
}

// MARK: - The tape

public struct HTMLTape: Sendable {
    /// A start tag's detail (name range + attribute span + self-closing), referenced from its slot's
    /// `low`. Kept out of the main tape so the hot token stream stays one dense `UInt64` per token.
    struct StartRecord: Sendable {
        var nameOff: UInt32
        var nameLen: UInt32
        var attrStart: UInt32
        var attrCount: UInt32
        var selfClosing: Bool
    }

    /// One attribute: name range + value range (value may need entity decoding). Zero-length value =
    /// a boolean/empty attribute (`disabled`).
    struct AttrRecord: Sendable {
        var nameOff: UInt32
        var nameLen: UInt32
        var valOff: UInt32
        var valLen: UInt32
        var valDecode: Bool
    }

    let source: [UInt8]
    let slots: ContiguousArray<UInt64>
    let starts: ContiguousArray<StartRecord>
    let attrs: ContiguousArray<AttrRecord>

    /// Number of tokens on the tape.
    public var count: Int { slots.count }

    /// Tokenize `html` into a tape. One pass over the UTF-8 bytes; allocations are the three growable
    /// arrays (pre-reserved) plus the owned source copy.
    public static func build(_ html: String) -> HTMLTape {
        let source = Array(html.utf8)
        guard !source.isEmpty else {
            return HTMLTape(source: source, slots: [], starts: [], attrs: [])
        }
        var scanner = Scanner(source)
        scanner.run()
        return HTMLTape(source: source, slots: scanner.slots, starts: scanner.starts, attrs: scanner.attrs)
    }
}

// MARK: - The byte scanner

extension HTMLTape {
    /// A one-pass tokenizer over a borrowed UTF-8 buffer. Local to `build`; the pointer never escapes.
    fileprivate struct Scanner {
        let bytes: [UInt8]
        let n: Int
        var slots = ContiguousArray<UInt64>()
        var starts = ContiguousArray<HTMLTape.StartRecord>()
        var attrs = ContiguousArray<HTMLTape.AttrRecord>()

        init(_ bytes: [UInt8]) {
            self.bytes = bytes  // shared COW buffer (no copy); HTMLTape keeps the same `source`
            self.n = bytes.count
            slots.reserveCapacity(n / 3 + 16)  // a token every few bytes; avoid mid-scan regrowth
            starts.reserveCapacity(n / 8 + 8)
            attrs.reserveCapacity(n / 12 + 8)
        }

        // Safe, bounds-checked byte read (every access funnels through here). No raw pointers: the
        // scanner stores the `[UInt8]` and the strict-memory-safety surface stays empty.
        @inline(__always) func b(_ k: Int) -> UInt8 { bytes[k] }
        @inline(__always) mutating func emit(_ tag: UInt8, _ off: Int, _ len: Int, _ decode: Bool = false) {
            slots.append(TapeSlot.make(tag: tag, aux: (UInt64(len) << 1) | (decode ? 1 : 0), low: off))
        }

        // Case-insensitive compare of base[off ..< off+lit.count] to an ASCII byte literal.
        func ciEqual(_ off: Int, _ lit: [UInt8]) -> Bool {
            for j in 0 ..< lit.count where lower(b(off + j)) != lit[j] { return false }
            return true
        }
        func matchesDoctype(_ off: Int) -> Bool { off + litDoctype.count <= n && ciEqual(off, litDoctype) }
        // `</name` matches when the name equals (case-insensitive) and the next byte ends the tag.
        func matchesEndName(_ at: Int, _ nameOff: Int, _ nameLen: Int) -> Bool {
            guard at + nameLen <= n else { return false }
            for j in 0 ..< nameLen where lower(b(at + j)) != lower(b(nameOff + j)) { return false }
            let after = at + nameLen
            if after >= n { return true }
            let c = b(after)
            return isSpace(c) || c == gt || c == slash
        }
        // Raw-text / RCDATA element? Returns the "decode entities" flag (true = RCDATA), or nil.
        func rawTextKind(_ nameOff: Int, _ nameLen: Int) -> Bool? {
            switch nameLen {
                case 3: return ciEqual(nameOff, rawXmp) ? false : nil
                case 5:
                    if ciEqual(nameOff, rawStyle) { return false }
                    if ciEqual(nameOff, rcTitle) { return true }
                    return nil
                case 6:
                    if ciEqual(nameOff, rawScript) { return false }
                    if ciEqual(nameOff, rawIframe) { return false }
                    return nil
                case 7: return ciEqual(nameOff, rawNoembed) ? false : nil
                case 8:
                    if ciEqual(nameOff, rawNoframes) { return false }
                    if ciEqual(nameOff, rcTextarea) { return true }
                    return nil
                default: return nil
            }
        }

        mutating func scanComment(_ cs: Int) -> Int {
            var k = cs
            while k + 2 < n, !(b(k) == dash && b(k + 1) == dash && b(k + 2) == gt) { k &+= 1 }
            if k + 2 < n {  // found `-->`
                emit(HTMLTapeKind.comment, cs, k - cs)
                return k + 3
            }
            emit(HTMLTapeKind.comment, cs, n - cs)
            return n
        }
        mutating func scanBogusComment(_ cs: Int) -> Int {
            var k = cs
            while k < n, b(k) != gt { k &+= 1 }
            emit(HTMLTapeKind.comment, cs, k - cs)
            return k < n ? k + 1 : n
        }
        mutating func scanDoctype(_ after: Int) -> Int {
            var k = after
            while k < n, isSpace(b(k)) { k &+= 1 }
            let nameStart = k
            while k < n, !isSpace(b(k)), b(k) != gt { k &+= 1 }
            let nameLen = k - nameStart
            while k < n, b(k) != gt { k &+= 1 }
            if k < n { k &+= 1 }
            if nameLen > 0 { emit(HTMLTapeKind.doctype, nameStart, nameLen) } else { emit(HTMLTapeKind.doctypeNil, 0, 0) }
            return k
        }
        mutating func scanEndTag(_ ns: Int) -> Int {
            var k = ns
            while k < n, !isSpace(b(k)), b(k) != slash, b(k) != gt { k &+= 1 }
            let nameLen = k - ns
            while k < n, b(k) != gt { k &+= 1 }
            if k < n { k &+= 1 }
            emit(HTMLTapeKind.endTag, ns, nameLen)
            return k
        }
        // Raw-text / RCDATA content runs verbatim to the matching end tag; markup inside is not parsed
        // (RCDATA additionally entity-decodes, flagged on the text slot).
        mutating func scanRawText(_ nameOff: Int, _ nameLen: Int, _ contentStart: Int, _ decode: Bool) -> Int {
            var i = contentStart
            while i < n {
                if b(i) == lt, i + 1 < n, b(i + 1) == slash, matchesEndName(i + 2, nameOff, nameLen) { break }
                i &+= 1
            }
            if i - contentStart > 0 { emit(HTMLTapeKind.text, contentStart, i - contentStart, decode) }
            if i < n {  // at `</name`
                let closeNameOff = i + 2
                var k = closeNameOff + nameLen
                while k < n, b(k) != gt { k &+= 1 }
                if k < n { k &+= 1 }
                emit(HTMLTapeKind.endTag, closeNameOff, nameLen)
                return k
            }
            return n
        }

        mutating func scanStartTag(_ ns: Int) -> Int {
            var k = ns
            while k < n, !isSpace(b(k)), b(k) != slash, b(k) != gt { k &+= 1 }
            let nameLen = k - ns
            let attrStart = attrs.count
            var selfClosing = false

            attributes: while k < n {
                while k < n, isSpace(b(k)) { k &+= 1 }
                if k >= n { break }
                let c = b(k)
                if c == gt {
                    k &+= 1
                    break
                }
                if c == slash {
                    k &+= 1
                    if k < n, b(k) == gt {
                        selfClosing = true
                        k &+= 1
                        break
                    }
                    continue
                }
                let anStart = k
                while k < n, !isSpace(b(k)), b(k) != eq, b(k) != slash, b(k) != gt { k &+= 1 }
                let anLen = k - anStart
                var avOff = 0
                var avLen = 0
                var avDecode = false
                while k < n, isSpace(b(k)) { k &+= 1 }
                if k < n, b(k) == eq {
                    k &+= 1
                    while k < n, isSpace(b(k)) { k &+= 1 }
                    if k < n, b(k) == dquote || b(k) == squote {
                        let q = b(k)
                        k &+= 1
                        avOff = k
                        while k < n, b(k) != q {
                            if b(k) == ampersand { avDecode = true }
                            k &+= 1
                        }
                        avLen = k - avOff
                        if k < n { k &+= 1 }  // closing quote
                    } else {  // unquoted value
                        avOff = k
                        while k < n, !isSpace(b(k)), b(k) != gt {
                            if b(k) == ampersand { avDecode = true }
                            k &+= 1
                        }
                        avLen = k - avOff
                    }
                }
                if anLen > 0 {
                    attrs.append(
                        HTMLTape.AttrRecord(
                            nameOff: UInt32(anStart), nameLen: UInt32(anLen),
                            valOff: UInt32(avOff), valLen: UInt32(avLen), valDecode: avDecode))
                }
            }

            let startIndex = starts.count
            starts.append(
                HTMLTape.StartRecord(
                    nameOff: UInt32(ns), nameLen: UInt32(nameLen),
                    attrStart: UInt32(attrStart), attrCount: UInt32(attrs.count - attrStart),
                    selfClosing: selfClosing))
            slots.append(TapeSlot.make(tag: HTMLTapeKind.startTag, aux: 0, low: startIndex))

            if !selfClosing, let decode = rawTextKind(ns, nameLen) { return scanRawText(ns, nameLen, k, decode) }
            return k
        }

        // Dispatch a `<...`: comment, doctype, end tag, start tag, or a literal `<`.
        mutating func handleLT(_ i: Int) -> Int {
            guard i + 1 < n else {  // a lone `<` at EOF is literal text
                emit(HTMLTapeKind.text, i, 1)
                return n
            }
            let c = b(i + 1)
            if c == bang {
                if i + 3 < n, b(i + 2) == dash, b(i + 3) == dash { return scanComment(i + 4) }
                if matchesDoctype(i + 2) { return scanDoctype(i + 9) }  // 2 + len("DOCTYPE")
                return scanBogusComment(i + 2)
            }
            if c == slash {
                if i + 2 < n, ASCII.isAlpha(b(i + 2)) { return scanEndTag(i + 2) }
                if i + 2 < n, b(i + 2) == gt { return i + 3 }  // `</>` — ignored
                return scanBogusComment(i + 2)
            }
            if ASCII.isAlpha(c) { return scanStartTag(i + 1) }
            emit(HTMLTapeKind.text, i, 1)  // literal `<`
            return i + 1
        }

        mutating func run() {
            var i = 0
            while i < n {
                if b(i) == lt {
                    i = handleLT(i)
                } else {
                    // Text run to the next `<`, flagging any `&` for lazy decode. Scalar (not SWAR):
                    // node-dense HTML has short text runs where SWAR's 8-byte stride is pure overhead
                    // (ADJSON measured the same regression for its whitespace skip).
                    let start = i
                    var decode = false
                    while i < n, b(i) != lt {
                        if b(i) == ampersand { decode = true }
                        i &+= 1
                    }
                    emit(HTMLTapeKind.text, start, i - start, decode)
                }
            }
        }
    }
}

// MARK: - Byte predicates + literals (value-only; no pointer access)

private let lt: UInt8 = 0x3C  // <
private let gt: UInt8 = 0x3E  // >
private let slash: UInt8 = 0x2F  // /
private let bang: UInt8 = 0x21  // !
private let dash: UInt8 = 0x2D  // -
private let eq: UInt8 = 0x3D  // =
private let ampersand: UInt8 = 0x26  // &
private let dquote: UInt8 = 0x22  // "
private let squote: UInt8 = 0x27  // '

@inline(__always) private func isSpace(_ b: UInt8) -> Bool {
    b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D
}
@inline(__always) private func lower(_ b: UInt8) -> UInt8 { ASCII.isUppercase(b) ? b &+ 0x20 : b }

private let rawScript = Array("script".utf8)
private let rawStyle = Array("style".utf8)
private let rawXmp = Array("xmp".utf8)
private let rawIframe = Array("iframe".utf8)
private let rawNoembed = Array("noembed".utf8)
private let rawNoframes = Array("noframes".utf8)
private let rcTitle = Array("title".utf8)
private let rcTextarea = Array("textarea".utf8)
private let litDoctype = Array("doctype".utf8)

// MARK: - Materialize (tape -> [HTMLToken], the correctness path; safe array access only)

extension HTMLTape {
    /// The token at tape index `i`, building Strings lazily (entity-decoded text/values, lowercased
    /// names). Tree construction will prefer this over `materialize()` to touch only what it needs.
    public func token(at i: Int) -> HTMLToken {
        let s = slots[i]
        switch TapeSlot.tag(s) {
            case HTMLTapeKind.text:
                let aux = TapeSlot.aux(s)
                return .text(text(TapeSlot.low(s), Int(aux >> 1), decode: aux & 1 == 1))
            case HTMLTapeKind.startTag:
                let rec = starts[TapeSlot.low(s)]
                var attributes: [HTMLAttribute] = []
                attributes.reserveCapacity(Int(rec.attrCount))
                for a in Int(rec.attrStart) ..< Int(rec.attrStart + rec.attrCount) {
                    let r = attrs[a]
                    let value = r.valLen == 0 ? "" : text(Int(r.valOff), Int(r.valLen), decode: r.valDecode)
                    attributes.append(
                        HTMLAttribute(name: lowerName(Int(r.nameOff), Int(r.nameLen)), value: value))
                }
                return .startTag(
                    name: lowerName(Int(rec.nameOff), Int(rec.nameLen)), attributes: attributes,
                    selfClosing: rec.selfClosing)
            case HTMLTapeKind.endTag:
                return .endTag(name: lowerName(TapeSlot.low(s), Int(TapeSlot.aux(s) >> 1)))
            case HTMLTapeKind.comment:
                return .comment(raw(TapeSlot.low(s), Int(TapeSlot.aux(s) >> 1)))
            case HTMLTapeKind.doctype:
                return .doctype(name: lowerName(TapeSlot.low(s), Int(TapeSlot.aux(s) >> 1)))
            default:
                return .doctype(name: nil)
        }
    }

    /// Reconstruct the full `[HTMLToken]` stream (the correctness oracle for the tape).
    public func materialize() -> [HTMLToken] {
        var out: [HTMLToken] = []
        out.reserveCapacity(slots.count)
        for i in 0 ..< slots.count { out.append(token(at: i)) }
        return out
    }

    private func raw(_ off: Int, _ len: Int) -> String {
        String(decoding: source[off ..< off + len], as: UTF8.self)
    }
    private func lowerName(_ off: Int, _ len: Int) -> String {
        var bytes = [UInt8]()
        bytes.reserveCapacity(len)
        for k in off ..< off + len { bytes.append(lower(source[k])) }
        return String(decoding: bytes, as: UTF8.self)
    }
    private func text(_ off: Int, _ len: Int, decode: Bool) -> String {
        decode ? decodeEntities(off, len) : raw(off, len)
    }

    /// Decode HTML entities in `source[off ..< off+len]`, copying non-entity byte runs verbatim
    /// (UTF-8-correct) and resolving `&name;` / `&#nnn;` / `&#xhh;` via the shared reference table.
    private func decodeEntities(_ off: Int, _ len: Int) -> String {
        var out = ""
        out.reserveCapacity(len)
        var j = off
        let end = off + len
        while j < end {
            if source[j] == ampersand, let (decoded, consumed) = decodeReference(j, end) {
                out += decoded
                j += consumed
            } else if source[j] == ampersand {
                out += "&"
                j += 1
            } else {
                let runStart = j
                while j < end, source[j] != ampersand { j += 1 }
                out += String(decoding: source[runStart ..< j], as: UTF8.self)
            }
        }
        return out
    }

    /// Decode one reference at `&` (index `j`): replacement + bytes consumed (incl. the `&`), or nil.
    private func decodeReference(_ j: Int, _ end: Int) -> (String, Int)? {
        var k = j + 1
        guard k < end else { return nil }
        if source[k] == 0x23 {  // '#': numeric
            k += 1
            var isHex = false
            if k < end, source[k] == 0x78 || source[k] == 0x58 {  // x / X
                isHex = true
                k += 1
            }
            var value: UInt32 = 0
            var any = false
            while k < end {
                let byte = source[k]
                let digit: UInt32
                if ASCII.isDigit(byte) {
                    digit = UInt32(byte - 0x30)
                } else if isHex, byte >= 0x61, byte <= 0x66 {
                    digit = UInt32(byte - 0x61 + 10)
                } else if isHex, byte >= 0x41, byte <= 0x46 {
                    digit = UInt32(byte - 0x41 + 10)
                } else {
                    break
                }
                value = value &* (isHex ? 16 : 10) &+ digit
                any = true
                k += 1
            }
            guard any else { return nil }
            if k < end, source[k] == 0x3B { k += 1 }  // optional ';'
            guard let scalar = Unicode.Scalar(value) else { return nil }
            return (String(scalar), k - j)
        }
        var p = k  // named: `&name;`
        while p < end, ASCII.isAlphanumeric(source[p]) { p += 1 }
        guard p < end, source[p] == 0x3B else { return nil }
        let name = String(decoding: source[k ..< p], as: UTF8.self)
        guard let replacement = namedCharacterReferences[name] else { return nil }
        return (replacement, (p + 1) - j)
    }
}
