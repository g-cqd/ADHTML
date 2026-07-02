// HTMLTokenizer — the WHATWG tokenization stage in pure Swift (the algorithm WebKit's
// HTMLTokenizer.cpp implements; https://html.spec.whatwg.org/#tokenization). A state
// machine over the input code points → a stream of start/end-tag, text, comment, and
// doctype tokens. Cross-platform, no WebView, no deprecated API.
//
// Scope: the states real documents exercise — tags + attributes (quoted/unquoted),
// character references (numeric + the common named set), comments, DOCTYPE, and the
// raw-text / RCDATA elements (script/style vs title/textarea) whose content must NOT be
// parsed as markup. The rarer states (CDATA sections, script-escape sub-states, the
// full ~2200-entry named table) are deferred; the tree-construction stage layers on top.

//
// This target (`ADHTMLOracle`) is NOT a product and NOT in `.adbuildtools.json` `shippedTargets`:
// the tokenizer exists only as the differential oracle for the shipping `HTMLTape` (HTMLTapeTests /
// HTMLTapeRobustnessTests / HTMLTokenizerTests) and for the dev `ADHTMLPerfProbe`. Its entity
// decoder is deliberately INDEPENDENT of `HTMLTape`'s (merging them would hollow out the
// differential property); only the pure named-reference DATA table is shared (`ADHTMLCore`'s
// `namedCharacterReferences`, `package`-visible) — shared data, independent decode logic.

// The token types (`HTMLToken` / `HTMLAttribute`) are the shipping module's — the differential
// compares values of the SAME type, so the oracle re-exports nothing of its own.
public import ADHTMLCore

// swiftlint:disable type_body_length file_length
// Deliberate size exceptions (out of the shipped-tree gate): this file mirrors the WHATWG
// tokenization states 1:1 — a spec-shaped single `Machine` is what makes it trustworthy as an
// oracle, so it is not decomposed to fit the shipped metrics. `Machine.step`'s cyclomatic/body
// suppression sits at its definition below for the same reason.
public enum HTMLTokenizer {
    public static func tokenize(_ html: String) -> [HTMLToken] {
        let machine = Machine(html)
        machine.run()
        return machine.output
    }
}

/// Elements whose content is raw text (no markup, no entity decoding) until the
/// matching end tag.
private let rawTextElements: Set<String> = ["script", "style", "xmp", "iframe", "noembed", "noframes"]
/// Elements whose content is RCDATA (entity decoding, but no markup) until the end tag.
private let rcdataElements: Set<String> = ["title", "textarea"]

private final class Machine {
    private enum State {
        case data, tagOpen, endTagOpen, tagName
        case beforeAttributeName, attributeName, afterAttributeName, beforeAttributeValue
        case attributeValueDoubleQuoted, attributeValueSingleQuoted, attributeValueUnquoted
        case afterAttributeValueQuoted, selfClosingStartTag
        case markupDeclarationOpen, bogusComment
        case commentStart, commentStartDash, comment, commentEndDash, commentEnd
        case doctype, beforeDoctypeName, doctypeName, afterDoctypeName, bogusDoctype
    }

    private let scalars: [Unicode.Scalar]
    private var index = 0
    private var state: State = .data
    var output: [HTMLToken] = []

    private var text = ""
    private var tagName = ""
    private var isEndTag = false
    private var selfClosing = false
    private var attributes: [HTMLAttribute] = []
    private var attributeName = ""
    private var attributeValue = ""
    private var comment = ""
    private var doctypeName = ""
    /// Set when a raw-text/RCDATA start tag is emitted; consumed by `run()` AFTER the
    /// start tag's `>` is consumed, so the element content reads from the right place.
    private var enterRawText: (name: String, decode: Bool)?

    init(_ html: String) {
        // Input preprocessing: normalize CRLF / CR to LF (stdlib only — the core is
        // Foundation-free).
        var normalized: [Unicode.Scalar] = []
        let raw = Array(html.unicodeScalars)
        normalized.reserveCapacity(raw.count)
        var i = 0
        while i < raw.count {
            if raw[i] == "\r" {
                normalized.append("\n")
                if i + 1 < raw.count, raw[i + 1] == "\n" { i += 1 }
            } else {
                normalized.append(raw[i])
            }
            i += 1
        }
        scalars = normalized
    }

    private var current: Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }
    private func advance() { index += 1 }

    private func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\t" || scalar == "\n" || scalar == "\u{0C}" || scalar == " "
    }
    private func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
    }
    private func lower(_ scalar: Unicode.Scalar) -> Character {
        if scalar >= "A" && scalar <= "Z" { return Character(Unicode.Scalar(scalar.value + 0x20)!) }
        return Character(scalar)
    }

    private func flushText() {
        if !text.isEmpty {
            output.append(.text(text))
            text = ""
        }
    }

    private func emitTagToken() {
        if isEndTag {
            flushText()
            output.append(.endTag(name: tagName))
            return
        }
        flushText()
        output.append(.startTag(name: tagName, attributes: attributes, selfClosing: selfClosing))
        // Raw-text / RCDATA elements: their content is consumed as text up to the close
        // tag — but only AFTER this start tag's `>` is consumed (see `run()`).
        if !selfClosing {
            if rawTextElements.contains(tagName) {
                enterRawText = (tagName, false)
            } else if rcdataElements.contains(tagName) {
                enterRawText = (tagName, true)
            }
        }
    }

    private func startTag(endTag: Bool) {
        tagName = ""
        isEndTag = endTag
        selfClosing = false
        attributes = []
    }
    private func appendAttribute() {
        if !attributeName.isEmpty {
            attributes.append(HTMLAttribute(name: attributeName, value: attributeValue))
        }
        attributeName = ""
        attributeValue = ""
    }

    func run() {
        while index <= scalars.count {
            if let raw = enterRawText {
                enterRawText = nil
                consumeTextElement(raw.name, decodeEntities: raw.decode)
                continue
            }
            if index == scalars.count {
                // EOF: flush any pending text + an unterminated comment, then stop.
                if state == .comment || state == .commentEnd || state == .commentEndDash
                    || state == .bogusComment
                {
                    flushText()
                    output.append(.comment(comment))
                }
                flushText()
                break
            }
            step(scalars[index])
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func step(_ scalar: Unicode.Scalar) {
        switch state {
            case .data:
                if scalar == "&" {
                    text += consumeCharacterReference()
                } else if scalar == "<" {
                    state = .tagOpen
                    advance()
                } else {
                    // Bulk-scan the text run to the next `<`/`&` and append it in one go
                    // (ADJSON's insight: work over ranges, not per character).
                    let start = index
                    while index < scalars.count, scalars[index] != "<", scalars[index] != "&" {
                        index += 1
                    }
                    text.unicodeScalars.append(contentsOf: scalars[start ..< index])
                }

            case .tagOpen:
                if scalar == "!" {
                    state = .markupDeclarationOpen
                    advance()
                } else if scalar == "/" {
                    state = .endTagOpen
                    advance()
                } else if isASCIIAlpha(scalar) {
                    startTag(endTag: false)
                    state = .tagName
                } else {
                    text += "<"
                    state = .data
                }

            case .endTagOpen:
                if isASCIIAlpha(scalar) {
                    startTag(endTag: true)
                    state = .tagName
                } else if scalar == ">" {
                    state = .data
                    advance()
                } else {
                    comment = ""
                    state = .bogusComment
                }

            case .tagName:
                if isWhitespace(scalar) {
                    state = .beforeAttributeName
                    advance()
                } else if scalar == "/" {
                    state = .selfClosingStartTag
                    advance()
                } else if scalar == ">" {
                    emitTagToken()
                    state = .data
                    advance()
                } else {
                    tagName.append(lower(scalar))
                    advance()
                }

            case .beforeAttributeName:
                if isWhitespace(scalar) {
                    advance()
                } else if scalar == "/" || scalar == ">" {
                    state = .afterAttributeName
                } else {
                    attributeName = ""
                    attributeValue = ""
                    state = .attributeName
                }

            case .attributeName:
                if isWhitespace(scalar) || scalar == "/" || scalar == ">" {
                    state = .afterAttributeName
                } else if scalar == "=" {
                    state = .beforeAttributeValue
                    advance()
                } else {
                    attributeName.append(lower(scalar))
                    advance()
                }

            case .afterAttributeName:
                if isWhitespace(scalar) {
                    advance()
                } else if scalar == "/" {
                    appendAttribute()
                    state = .selfClosingStartTag
                    advance()
                } else if scalar == "=" {
                    state = .beforeAttributeValue
                    advance()
                } else if scalar == ">" {
                    appendAttribute()
                    emitTagToken()
                    state = .data
                    advance()
                } else {
                    appendAttribute()
                    attributeName = ""
                    state = .attributeName
                }

            case .beforeAttributeValue:
                if isWhitespace(scalar) {
                    advance()
                } else if scalar == "\"" {
                    state = .attributeValueDoubleQuoted
                    advance()
                } else if scalar == "'" {
                    state = .attributeValueSingleQuoted
                    advance()
                } else if scalar == ">" {
                    appendAttribute()
                    emitTagToken()
                    state = .data
                    advance()
                } else {
                    state = .attributeValueUnquoted
                }

            case .attributeValueDoubleQuoted:
                if scalar == "\"" {
                    state = .afterAttributeValueQuoted
                    advance()
                } else if scalar == "&" {
                    attributeValue += consumeCharacterReference()
                } else {
                    attributeValue.unicodeScalars.append(scalar)
                    advance()
                }

            case .attributeValueSingleQuoted:
                if scalar == "'" {
                    state = .afterAttributeValueQuoted
                    advance()
                } else if scalar == "&" {
                    attributeValue += consumeCharacterReference()
                } else {
                    attributeValue.unicodeScalars.append(scalar)
                    advance()
                }

            case .attributeValueUnquoted:
                if isWhitespace(scalar) {
                    appendAttribute()
                    state = .beforeAttributeName
                    advance()
                } else if scalar == "&" {
                    attributeValue += consumeCharacterReference()
                } else if scalar == ">" {
                    appendAttribute()
                    emitTagToken()
                    state = .data
                    advance()
                } else {
                    attributeValue.unicodeScalars.append(scalar)
                    advance()
                }

            case .afterAttributeValueQuoted:
                appendAttribute()
                if isWhitespace(scalar) {
                    state = .beforeAttributeName
                    advance()
                } else if scalar == "/" {
                    state = .selfClosingStartTag
                    advance()
                } else if scalar == ">" {
                    emitTagToken()
                    state = .data
                    advance()
                } else {
                    state = .beforeAttributeName
                }

            case .selfClosingStartTag:
                if scalar == ">" {
                    appendAttribute()
                    selfClosing = true
                    emitTagToken()
                    state = .data
                    advance()
                } else {
                    state = .beforeAttributeName
                }

            case .markupDeclarationOpen:
                if matches("--") {
                    index += 2
                    comment = ""
                    state = .commentStart
                } else if matchesCaseless("DOCTYPE") {
                    index += 7
                    state = .doctype
                } else {
                    comment = ""
                    state = .bogusComment
                }

            case .bogusComment:
                if scalar == ">" {
                    flushText()
                    output.append(.comment(comment))
                    state = .data
                    advance()
                } else {
                    comment.unicodeScalars.append(scalar)
                    advance()
                }

            case .commentStart:
                if scalar == "-" {
                    state = .commentStartDash
                    advance()
                } else if scalar == ">" {
                    flushText()
                    output.append(.comment(comment))
                    state = .data
                    advance()
                } else {
                    state = .comment
                }

            case .commentStartDash:
                if scalar == "-" {
                    state = .commentEnd
                    advance()
                } else {
                    comment += "-"
                    state = .comment
                }

            case .comment:
                if scalar == "-" {
                    state = .commentEndDash
                    advance()
                } else {
                    comment.unicodeScalars.append(scalar)
                    advance()
                }

            case .commentEndDash:
                if scalar == "-" {
                    state = .commentEnd
                    advance()
                } else {
                    comment += "-"
                    state = .comment
                }

            case .commentEnd:
                if scalar == ">" {
                    flushText()
                    output.append(.comment(comment))
                    state = .data
                    advance()
                } else if scalar == "-" {
                    comment += "-"
                    advance()
                } else {
                    comment += "--"
                    state = .comment
                }

            case .doctype:
                if isWhitespace(scalar) { advance() }
                doctypeName = ""
                state = .beforeDoctypeName

            case .beforeDoctypeName:
                if isWhitespace(scalar) {
                    advance()
                } else if scalar == ">" {
                    flushText()
                    output.append(.doctype(name: nil))
                    state = .data
                    advance()
                } else {
                    doctypeName.append(lower(scalar))
                    state = .doctypeName
                    advance()
                }

            case .doctypeName:
                if isWhitespace(scalar) {
                    state = .afterDoctypeName
                    advance()
                } else if scalar == ">" {
                    flushText()
                    output.append(.doctype(name: doctypeName.isEmpty ? nil : doctypeName))
                    state = .data
                    advance()
                } else {
                    doctypeName.append(lower(scalar))
                    advance()
                }

            case .afterDoctypeName:
                if scalar == ">" {
                    flushText()
                    output.append(.doctype(name: doctypeName.isEmpty ? nil : doctypeName))
                    state = .data
                    advance()
                } else {
                    state = .bogusDoctype
                    advance()
                }

            case .bogusDoctype:
                if scalar == ">" {
                    flushText()
                    output.append(.doctype(name: doctypeName.isEmpty ? nil : doctypeName))
                    state = .data
                }
                advance()
        }
    }

    // MARK: - raw-text / RCDATA element content

    /// Consume the content of a raw-text/RCDATA element up to its matching end tag,
    /// emitting a text token (entity-decoded for RCDATA) then the end tag.
    private func consumeTextElement(_ name: String, decodeEntities: Bool) {
        var content = ""
        while index < scalars.count {
            if scalars[index] == "<", index + 1 < scalars.count, scalars[index + 1] == "/",
                matchesEndTag(name, at: index + 2)
            {
                // `</name` followed by whitespace, `/`, or `>`.
                flushText()
                if !content.isEmpty {
                    output.append(.text(decodeEntities ? Self.decode(content) : content))
                }
                index += 2 + name.count
                while index < scalars.count, isWhitespace(scalars[index]) { advance() }
                if index < scalars.count, scalars[index] == ">" { advance() }
                output.append(.endTag(name: name))
                return
            }
            content.unicodeScalars.append(scalars[index])
            advance()
        }
        // EOF without a close tag: emit what we have.
        flushText()
        if !content.isEmpty {
            output.append(.text(decodeEntities ? Self.decode(content) : content))
        }
    }

    private func matchesEndTag(_ name: String, at start: Int) -> Bool {
        let chars = Array(name)
        guard start + chars.count <= scalars.count else { return false }
        for (offset, character) in chars.enumerated() where lower(scalars[start + offset]) != character {
            return false
        }
        let after = start + chars.count
        guard after < scalars.count else { return true }
        let next = scalars[after]
        return isWhitespace(next) || next == ">" || next == "/"
    }

    // MARK: - literal lookahead

    private func matches(_ literal: String) -> Bool {
        let chars = Array(literal.unicodeScalars)
        guard index + chars.count <= scalars.count else { return false }
        for (offset, character) in chars.enumerated() where scalars[index + offset] != character {
            return false
        }
        return true
    }
    private func matchesCaseless(_ literal: String) -> Bool {
        let chars = Array(literal.lowercased())
        guard index + chars.count <= scalars.count else { return false }
        for (offset, character) in chars.enumerated() where lower(scalars[index + offset]) != character {
            return false
        }
        return true
    }

    // MARK: - character references

    /// At a `&`, decode a numeric or named character reference, advancing past it.
    /// Returns the decoded string, or `"&"` (advancing only past the `&`) when there's
    /// no valid reference.
    private func consumeCharacterReference() -> String {
        // index is at `&`.
        let start = index
        advance()  // consume `&`
        guard index < scalars.count else { return "&" }
        if scalars[index] == "#" {
            advance()
            var isHex = false
            if index < scalars.count, scalars[index] == "x" || scalars[index] == "X" {
                isHex = true
                advance()
            }
            var digits = ""
            while index < scalars.count {
                let scalar = scalars[index]
                let isDigit = scalar >= "0" && scalar <= "9"
                let isHexDigit =
                    isDigit || (scalar >= "a" && scalar <= "f") || (scalar >= "A" && scalar <= "F")
                guard isHex ? isHexDigit : isDigit else {
                    break
                }
                digits.unicodeScalars.append(scalar)
                advance()
            }
            if index < scalars.count, scalars[index] == ";" { advance() }
            if let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                return String(scalar)
            }
            index = start
            advance()
            return "&"
        }
        // Named reference: `&name;`.
        var name = ""
        var probe = index
        while probe < scalars.count, isASCIIAlphaNumeric(scalars[probe]) {
            name.unicodeScalars.append(scalars[probe])
            probe += 1
        }
        if probe < scalars.count, scalars[probe] == ";", let replacement = namedCharacterReferences[name] {
            index = probe + 1
            return replacement
        }
        return "&"
    }

    private func isASCIIAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        isASCIIAlpha(scalar) || (scalar >= "0" && scalar <= "9")
    }

    /// Decode entities in RCDATA text (a thin wrapper running the same `&name;`/numeric
    /// logic over a finished string).
    static func decode(_ text: String) -> String {
        var machine = ""
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            if scalars[i] == "&" {
                let sub = Machine.decodeOne(scalars, &i)
                machine += sub
            } else {
                machine.unicodeScalars.append(scalars[i])
                i += 1
            }
        }
        return machine
    }

    private static func decodeOne(_ scalars: [Unicode.Scalar], _ i: inout Int) -> String {
        let start = i
        i += 1
        guard i < scalars.count else { return "&" }
        if scalars[i] == "#" {
            i += 1
            var isHex = false
            if i < scalars.count, scalars[i] == "x" || scalars[i] == "X" {
                isHex = true
                i += 1
            }
            var digits = ""
            while i < scalars.count {
                let s = scalars[i]
                let isDigit = s >= "0" && s <= "9"
                let isHexDigit = isDigit || (s >= "a" && s <= "f") || (s >= "A" && s <= "F")
                guard isHex ? isHexDigit : isDigit else { break }
                digits.unicodeScalars.append(s)
                i += 1
            }
            if i < scalars.count, scalars[i] == ";" { i += 1 }
            if let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                return String(scalar)
            }
            i = start + 1
            return "&"
        }
        var name = ""
        var probe = i
        while probe < scalars.count,
            isASCIIAlpha(scalars[probe]) || (scalars[probe] >= "0" && scalars[probe] <= "9")
        {
            name.unicodeScalars.append(scalars[probe])
            probe += 1
        }
        if probe < scalars.count, scalars[probe] == ";", let replacement = namedCharacterReferences[name] {
            i = probe + 1
            return replacement
        }
        i = start + 1
        return "&"
    }

    private static func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
    }
}
