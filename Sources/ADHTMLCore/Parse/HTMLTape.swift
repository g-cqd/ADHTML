// HTMLTape — the high-performance byte-level HTML tokenizer. Where `HTMLTokenizer` (the
// correctness-first reference, now in the non-shipped `ADHTMLOracle` target) is a
// `[Unicode.Scalar]` state machine emitting `[HTMLToken]` with a String per token, this scans
// the raw UTF-8 bytes ONCE into a single flat preorder tape of
// `UInt64` slots holding zero-copy (offset, length) ranges — no per-token String, no scalar
// expansion, and (crucially) NO side allocations: a start tag and its attributes are encoded inline
// in the one tape (ADJSON's "everything in the tape" rule), so a build allocates exactly twice — the
// owned source bytes and the slot array — with zero per-node heap traffic.
//
// Built on the family's shared kernels: `ADFCore.TapeSlot` (the slot bit-packing, promoted from
// ADJSON) and `ADFCore.ASCII`. Byte access is a raw `UnsafePointer<UInt8>` threaded as a parameter
// with `unsafe` at the read sites — the same pattern ADFCore.ByteCompare / ADHTMLCore.URLScheme use,
// and the path ADJSON deliberately takes for decode speed (its Span note is a Codable constraint, not
// a perf one). `materialize()` reconstructs `[HTMLToken]` (lazy entity-decode + name-lowercasing) so
// the reference tokenizer remains the differential oracle; tree construction walks the tape directly.

import ADFCore

// MARK: - Slot kinds (the 4-bit TapeSlot tag)

private enum K {
    static let text: UInt8 = 0  // aux = (length << 1) | needsDecode,        low = byte offset
    static let startTag: UInt8 = 1  // aux = (nameLen << 15) | (attrCount << 1) | selfClosing, low = name off
    static let endTag: UInt8 = 2  // aux = nameLen,                          low = name offset
    static let comment: UInt8 = 3  // aux = length,                          low = body offset
    static let doctype: UInt8 = 4  // aux = nameLen,                         low = name offset
    static let doctypeNil: UInt8 = 5  // a DOCTYPE with no name
    static let attrName: UInt8 = 6  // aux = length,                          low = offset (follows startTag)
    static let attrValue: UInt8 = 7  // aux = (length << 1) | needsDecode,     low = offset (follows attrName)

    static let maxNameLen = 0xFFF  // 12 bits
    static let maxAttrCount = 0x3FFF  // 14 bits
}

// MARK: - The tape

public struct HTMLTape: Sendable {
    let source: [UInt8]
    let slots: ContiguousArray<UInt64>

    /// Number of raw slots (start tags with attributes span more than one slot — walk with
    /// `materialize()` / `token(at:)` / `nextIndex(after:)`, not by treating each slot as a token).
    public var slotCount: Int { slots.count }

    /// Tokenize `html` into a tape. One pass over the UTF-8 bytes; allocations are the owned source
    /// copy plus the single pre-reserved slot array — no per-node heap traffic.
    public static func build(_ html: String) -> HTMLTape {
        let source = Array(html.utf8)
        guard !source.isEmpty else { return HTMLTape(source: source, slots: []) }
        var scanner = Scanner(n: source.count)
        source.withUnsafeBufferPointer { buf in
            // `baseAddress` is nil only for an empty buffer, which the guard above already
            // returned; bind instead of force-unwrapping so the impossible case is a no-op
            // (empty tape) rather than a trap.
            guard let base = buf.baseAddress else { return }
            unsafe scanner.run(base)
        }
        return HTMLTape(source: source, slots: scanner.slots)
    }
}

// MARK: - The byte scanner

extension HTMLTape {
    /// One-pass tokenizer. Holds only the growing tape (+ length); the byte pointer is a parameter,
    /// not storage, so there is no unsafe struct state and the pointer cannot escape `build`.
    fileprivate struct Scanner {
        var slots = ContiguousArray<UInt64>()
        let n: Int

        init(n: Int) {
            self.n = n
            slots.reserveCapacity(n / 3 + 16)  // a token every few bytes; avoid mid-scan regrowth
        }

        @inline(__always) mutating func emit(_ tag: UInt8, _ off: Int, _ aux: UInt64) {
            slots.append(TapeSlot.make(tag: tag, aux: aux, low: off))
        }

        mutating func run(_ p: UnsafePointer<UInt8>) {
            var i = 0
            while i < n {
                if unsafe (p[i] == lt) {
                    i = unsafe handleLT(p, i)
                } else {
                    let start = i
                    var decode = false
                    unsafe scanText(p, &i, &decode)
                    emit(K.text, start, (UInt64(i - start) << 1) | (decode ? 1 : 0))
                }
            }
        }

        // Advance `i` to the next `<` (or EOF), flagging `decode` if a `&` is seen. Short runs stay
        // pure scalar (no SWAR setup — node-dense/realistic markup, which a per-byte SWAR check
        // regresses); a run that survives a 16-byte scalar probe switches to SWAR word-skipping, so
        // only genuinely long text (prose) pays for — and benefits from — the 8-byte stride.
        @inline(__always)
        func scanText(_ p: UnsafePointer<UInt8>, _ i: inout Int, _ decode: inout Bool) {
            let cap = min(n, i + 16)
            while i < cap {
                let c = unsafe p[i]
                if c == lt { return }
                if c == ampersand { decode = true }
                i &+= 1
            }
            while i < n {
                while i + 8 <= n {
                    let w = unsafe UnsafeRawPointer(p + i).loadUnaligned(as: UInt64.self)
                    if (SWAR.equals(w, lt) | SWAR.equals(w, ampersand)) != 0 { break }
                    i &+= 8
                }
                let wordEnd = min(n, i + 8)
                while i < wordEnd {
                    let c = unsafe p[i]
                    if c == lt { return }
                    if c == ampersand { decode = true }
                    i &+= 1
                }
            }
        }

        // Dispatch a `<...`: comment, doctype, end tag, start tag, or a literal `<`. Returns next index.
        mutating func handleLT(_ p: UnsafePointer<UInt8>, _ i: Int) -> Int {
            guard i + 1 < n else {
                emit(K.text, i, 1 << 1)  // lone `<` at EOF is literal text
                return n
            }
            let c = unsafe p[i + 1]
            if c == bang {
                if i + 3 < n, unsafe (p[i + 2] == dash), unsafe (p[i + 3] == dash) {
                    return unsafe scanComment(p, i + 4)
                }
                if unsafe matchesDoctype(p, i + 2) { return unsafe scanDoctype(p, i + 9) }  // 2 + "DOCTYPE"
                return unsafe scanBogusComment(p, i + 2)
            }
            if c == slash {
                if i + 2 < n, ASCII.isAlpha(unsafe p[i + 2]) { return unsafe scanEndTag(p, i + 2) }
                if i + 2 < n, unsafe (p[i + 2] == gt) { return i + 3 }  // `</>` — ignored
                return unsafe scanBogusComment(p, i + 2)
            }
            if ASCII.isAlpha(c) { return unsafe scanStartTag(p, i + 1) }
            emit(K.text, i, 1 << 1)  // literal `<`
            return i + 1
        }

        // A start tag and its attributes, encoded inline: the start-tag slot (with nameLen, attrCount,
        // selfClosing backpatched once the count is known) followed by one (attrName, attrValue) slot
        // pair per attribute. No side arrays.
        mutating func scanStartTag(_ p: UnsafePointer<UInt8>, _ ns: Int) -> Int {
            var k = ns
            while k < n {
                let c = unsafe p[k]
                if isSpace(c) || c == slash || c == gt { break }
                k &+= 1
            }
            let nameLen = k - ns
            let startSlot = slots.count
            slots.append(0)  // placeholder; backpatched below
            var attrCount = 0
            var selfClosing = false

            while k < n {
                while k < n, isSpace(unsafe p[k]) { k &+= 1 }
                if k >= n { break }
                let c = unsafe p[k]
                if c == gt {
                    k &+= 1
                    break
                }
                if c == slash {
                    k &+= 1
                    if k < n, unsafe (p[k] == gt) {
                        selfClosing = true
                        k &+= 1
                        break
                    }
                    continue
                }
                if unsafe scanAttribute(p, &k) { attrCount &+= 1 }
            }

            let nameField = UInt64(min(nameLen, K.maxNameLen)) << 15
            let attrField = UInt64(min(attrCount, K.maxAttrCount)) << 1
            slots[startSlot] = TapeSlot.make(
                tag: K.startTag, aux: nameField | attrField | (selfClosing ? 1 : 0), low: ns)

            if !selfClosing, let decode = unsafe rawTextKind(p, ns, nameLen) {
                return unsafe scanRawText(p, ns, nameLen, k, decode)
            }
            return k
        }

        // One attribute: `name`, then an optional `=value` (quoted or unquoted). Advances `k` past it
        // and returns whether a (name, value) slot pair was emitted — a bare `=`/value with no name is
        // consumed but dropped, matching the prior inline behavior.
        private mutating func scanAttribute(_ p: UnsafePointer<UInt8>, _ k: inout Int) -> Bool {
            let anStart = k
            while k < n {
                let a = unsafe p[k]
                if isSpace(a) || a == eq || a == slash || a == gt { break }
                k &+= 1
            }
            let anLen = k - anStart
            let (avOff, avLen, avDecode) = unsafe scanAttributeValue(p, &k)
            guard anLen > 0 else { return false }
            emit(K.attrName, anStart, UInt64(anLen))
            emit(K.attrValue, avOff, (UInt64(avLen) << 1) | (avDecode ? 1 : 0))
            return true
        }

        // The optional `=value` following an attribute name. Returns (offset, length, needsEntityDecode),
        // or (0, 0, false) when there is no `=`. Handles double/single-quoted and unquoted values; sets
        // `decode` when an `&` appears (a possible entity reference).
        private mutating func scanAttributeValue(
            _ p: UnsafePointer<UInt8>, _ k: inout Int
        ) -> (off: Int, len: Int, decode: Bool) {
            while k < n, isSpace(unsafe p[k]) { k &+= 1 }
            guard k < n, unsafe (p[k] == eq) else { return (0, 0, false) }
            k &+= 1
            while k < n, isSpace(unsafe p[k]) { k &+= 1 }
            var avDecode = false
            if k < n, unsafe (p[k] == dquote || p[k] == squote) {
                let q = unsafe p[k]
                k &+= 1
                let avOff = k
                while k < n {
                    let v = unsafe p[k]
                    if v == q { break }
                    if v == ampersand { avDecode = true }
                    k &+= 1
                }
                let avLen = k - avOff
                if k < n { k &+= 1 }  // closing quote
                return (avOff, avLen, avDecode)
            }
            let avOff = k
            while k < n {
                let v = unsafe p[k]
                if isSpace(v) || v == gt { break }
                if v == ampersand { avDecode = true }
                k &+= 1
            }
            return (avOff, k - avOff, avDecode)
        }

        // Raw-text / RCDATA content runs verbatim to the matching end tag; markup inside is not parsed
        // (RCDATA additionally entity-decodes, flagged on the text slot).
        mutating func scanRawText(
            _ p: UnsafePointer<UInt8>, _ nameOff: Int, _ nameLen: Int, _ contentStart: Int, _ decode: Bool
        ) -> Int {
            var i = contentStart
            while i < n {
                if unsafe (p[i] == lt), i + 1 < n, unsafe (p[i + 1] == slash),
                    unsafe matchesEndName(p, i + 2, nameOff, nameLen)
                {
                    break
                }
                i &+= 1
            }
            if i - contentStart > 0 {
                emit(K.text, contentStart, (UInt64(i - contentStart) << 1) | (decode ? 1 : 0))
            }
            if i < n {  // at `</name`
                let closeNameOff = i + 2
                var k = closeNameOff + nameLen
                while k < n, unsafe (p[k] != gt) { k &+= 1 }
                if k < n { k &+= 1 }
                emit(K.endTag, closeNameOff, UInt64(nameLen))
                return k
            }
            return n
        }

        mutating func scanEndTag(_ p: UnsafePointer<UInt8>, _ ns: Int) -> Int {
            var k = ns
            while k < n {
                let c = unsafe p[k]
                if isSpace(c) || c == slash || c == gt { break }
                k &+= 1
            }
            let nameLen = k - ns
            while k < n, unsafe (p[k] != gt) { k &+= 1 }
            if k < n { k &+= 1 }
            emit(K.endTag, ns, UInt64(nameLen))
            return k
        }

        mutating func scanComment(_ p: UnsafePointer<UInt8>, _ cs: Int) -> Int {
            var k = cs
            while k + 2 < n, unsafe (!(p[k] == dash && p[k + 1] == dash && p[k + 2] == gt)) {
                k &+= 1
            }
            if k + 2 < n {  // found `-->`
                emit(K.comment, cs, UInt64(k - cs))
                return k + 3
            }
            emit(K.comment, cs, UInt64(n - cs))
            return n
        }

        mutating func scanBogusComment(_ p: UnsafePointer<UInt8>, _ cs: Int) -> Int {
            var k = cs
            while k < n, unsafe (p[k] != gt) { k &+= 1 }
            emit(K.comment, cs, UInt64(k - cs))
            return k < n ? k + 1 : n
        }

        mutating func scanDoctype(_ p: UnsafePointer<UInt8>, _ after: Int) -> Int {
            var k = after
            while k < n, isSpace(unsafe p[k]) { k &+= 1 }
            let nameStart = k
            while k < n {
                let c = unsafe p[k]
                if isSpace(c) || c == gt { break }
                k &+= 1
            }
            let nameLen = k - nameStart
            while k < n, unsafe (p[k] != gt) { k &+= 1 }
            if k < n { k &+= 1 }
            if nameLen > 0 { emit(K.doctype, nameStart, UInt64(nameLen)) } else { emit(K.doctypeNil, 0, 0) }
            return k
        }

        // Case-insensitive compare of p[off ..< off+lit.count] to an ASCII byte literal. Kept local:
        // ADFCore.ByteCompare offers only case-SENSITIVE pointer equality, so there is no foundation
        // primitive to dedup onto (the per-byte `lower` is already built on ADFCore.ASCII).
        func ciEqual(_ p: UnsafePointer<UInt8>, _ off: Int, _ lit: [UInt8]) -> Bool {
            for j in 0 ..< lit.count where lower(unsafe p[off + j]) != lit[j] { return false }
            return true
        }
        func matchesDoctype(_ p: UnsafePointer<UInt8>, _ off: Int) -> Bool {
            guard off + litDoctype.count <= n else { return false }
            return unsafe ciEqual(p, off, litDoctype)
        }
        // `</name` matches when the name equals (case-insensitive) and the next byte ends the tag.
        func matchesEndName(_ p: UnsafePointer<UInt8>, _ at: Int, _ nameOff: Int, _ nameLen: Int) -> Bool {
            guard at + nameLen <= n else { return false }
            for j in 0 ..< nameLen where lower(unsafe p[at + j]) != lower(unsafe p[nameOff + j]) {
                return false
            }
            let after = at + nameLen
            if after >= n { return true }
            let c = unsafe p[after]
            return isSpace(c) || c == gt || c == slash
        }
        // Raw-text / RCDATA element? Returns the "decode entities" flag (true = RCDATA), or nil. A
        // length switch rejects ordinary tags before any byte compare.
        func rawTextKind(_ p: UnsafePointer<UInt8>, _ nameOff: Int, _ nameLen: Int) -> Bool? {
            switch nameLen {
                case 3: return unsafe ciEqual(p, nameOff, rawXmp) ? false : nil
                case 5:
                    if unsafe ciEqual(p, nameOff, rawStyle) { return false }
                    if unsafe ciEqual(p, nameOff, rcTitle) { return true }
                    return nil
                case 6:
                    if unsafe ciEqual(p, nameOff, rawScript) { return false }
                    if unsafe ciEqual(p, nameOff, rawIframe) { return false }
                    return nil
                case 7: return unsafe ciEqual(p, nameOff, rawNoembed) ? false : nil
                case 8:
                    if unsafe ciEqual(p, nameOff, rawNoframes) { return false }
                    if unsafe ciEqual(p, nameOff, rcTextarea) { return true }
                    return nil
                default: return nil
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

/// HTML "ASCII whitespace" (WHATWG infra §4.7): TAB, LF, FF, CR, SPACE. Deliberately NOT deduped
/// onto an `ADFCore.ASCII` predicate — the foundation has no whitespace classifier, and HTML's set
/// differs from other formats' (e.g. JSON's insignificant whitespace has no FF), so encoding the
/// spec's exact set here keeps the tokenizer's semantics local and spec-true.
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
    /// The token starting at slot `i` plus the index of the next token's first slot. A start tag
    /// consumes its inline attribute slots here, so the returned index skips past them.
    func decoded(at i: Int) -> (HTMLToken, next: Int) {
        let s = slots[i]
        switch TapeSlot.tag(s) {
            case K.text:
                let aux = TapeSlot.aux(s)
                return (.text(text(TapeSlot.low(s), Int(aux >> 1), decode: aux & 1 == 1)), i + 1)
            case K.startTag:
                let aux = TapeSlot.aux(s)
                let selfClosing = aux & 1 == 1
                let attrCount = Int((aux >> 1) & 0x3FFF)
                let nameLen = Int((aux >> 15) & 0xFFF)
                var attributes: [HTMLAttribute] = []
                attributes.reserveCapacity(attrCount)
                var idx = i + 1
                for _ in 0 ..< attrCount {
                    let nameSlot = slots[idx]
                    let valueSlot = slots[idx + 1]
                    idx += 2
                    let vAux = TapeSlot.aux(valueSlot)
                    let vLen = Int(vAux >> 1)
                    let value = vLen == 0 ? "" : text(TapeSlot.low(valueSlot), vLen, decode: vAux & 1 == 1)
                    attributes.append(
                        HTMLAttribute(
                            name: lowerName(TapeSlot.low(nameSlot), Int(TapeSlot.aux(nameSlot))),
                            value: value))
                }
                return (
                    .startTag(
                        name: lowerName(TapeSlot.low(s), nameLen), attributes: attributes,
                        selfClosing: selfClosing), idx
                )
            case K.endTag:
                return (.endTag(name: lowerName(TapeSlot.low(s), Int(TapeSlot.aux(s)))), i + 1)
            case K.comment:
                return (.comment(raw(TapeSlot.low(s), Int(TapeSlot.aux(s)))), i + 1)
            case K.doctype:
                return (.doctype(name: lowerName(TapeSlot.low(s), Int(TapeSlot.aux(s)))), i + 1)
            default:
                return (.doctype(name: nil), i + 1)
        }
    }

    /// The token starting at slot `i` (ignoring navigation). `i` must be a token-start slot.
    public func token(at i: Int) -> HTMLToken { decoded(at: i).0 }

    /// The first slot of the token after the one at `i`.
    public func nextIndex(after i: Int) -> Int { decoded(at: i).next }

    /// Reconstruct the full `[HTMLToken]` stream (the correctness oracle for the tape).
    public func materialize() -> [HTMLToken] {
        var out: [HTMLToken] = []
        out.reserveCapacity(slots.count)
        var i = 0
        while i < slots.count {
            let (tok, next) = decoded(at: i)
            out.append(tok)
            i = next
        }
        return out
    }

    private func raw(_ off: Int, _ len: Int) -> String {
        String(decoding: source[off ..< off + len], as: UTF8.self)
    }
    private func lowerName(_ off: Int, _ len: Int) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(len)
        for k in off ..< off + len { bytes.append(lower(source[k])) }
        return String(decoding: bytes, as: UTF8.self)
    }
    private func text(_ off: Int, _ len: Int, decode: Bool) -> String {
        decode ? decodeEntities(off, len) : raw(off, len)
    }

    /// Decode HTML entities in `source[off ..< off+len]`, copying non-entity byte runs verbatim
    /// (UTF-8-correct) and resolving `&name;` / `&#nnn;` / `&#xhh;` via the shared
    /// `namedCharacterReferences` DATA table.
    ///
    /// DEDUP BOUNDARY (deliberate): the `ADHTMLOracle` reference tokenizer carries its own,
    /// independent entity decoder over `[Unicode.Scalar]`. Only the named-reference TABLE (pure
    /// spec data, `NamedCharacterReferences.swift`) is shared — merging the decode LOGIC would
    /// hollow out the differential property the HTMLTape tests rely on (two independent
    /// implementations agreeing). Do not unify them.
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
                // Digit classification/valuation via the ADFCore kernels (`Hex.value` is the family's
                // one hex-digit decoder) instead of hand-rolled byte ranges; accumulation order and
                // termination are unchanged.
                let byte = source[k]
                let digit: UInt32
                if isHex {
                    guard let nibble = Hex.value(byte) else { break }
                    digit = UInt32(nibble)
                } else {
                    guard ASCII.isDigit(byte) else { break }
                    digit = UInt32(byte - 0x30)
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
