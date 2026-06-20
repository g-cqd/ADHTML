// Component-scoped CSS (Track 4). A `ScopedStyle(.scoped)`'s CSS is prefixed so it can only match inside
// the component that declared it: every top-level selector gains a `[data-1="<scope>"] ` ancestor (the
// `WireToken.scope` attribute the engine stamps on the component's mount root). This is a single-pass byte
// state machine over the author's TRUSTED `StaticString` CSS, NOT a full CSS parser — it has a documented
// boundary (below), and an out-of-scope construct degrades to one prefixed selector, never invalid CSS:
//
//   • brace-depth 0: each comma-separated top-level selector is prefixed (commas inside `()`/`[]` and
//     inside strings/comments do not split);
//   • `@media` / `@supports`: recurse ONE level — the rules inside are scoped, the prelude copied;
//   • `@keyframes` / `@font-face` / `@page` / `@import` / other at-rules: copied VERBATIM (their bodies are
//     keyframe stops or descriptors, not page selectors);
//   • `:global(<sel>)` / `:global <sel>` / a `.global` class: opt OUT of scoping (CSS-Modules convention);
//   • the bytes inside a normal rule (declarations) are copied verbatim.
//
// Each unique component type is scoped at most once PER RENDER — the ``AssetSink`` dedups by scope hash
// BEFORE calling the scoper, so there is no process-global cache to grow unbounded in a long-running server.

/// Scopes a component's CSS to a `[data-…scope…]` ancestor — the Swift-native half of the bundling boundary
/// (CSS scoping is small, server-side, render-time; JS bundling stays bun's job).
public enum CSSScoper {
    /// Scope `css` so every top-level selector is confined under `[<scopeAttribute>="<scope>"]`. Pure (no
    /// shared state): the ``AssetSink`` dedups by scope before calling this, so it runs once per unique type.
    public static func scope(_ css: [UInt8], scope: String, scopeAttribute: String = WireToken.scope) -> [UInt8] {
        // The ancestor-prefix inserted before each scoped selector: `[data-1="<scope>"] `.
        var prefix: [UInt8] = [openBracket]
        prefix.append(contentsOf: scopeAttribute.utf8)
        prefix.append(equals)
        prefix.append(quote)
        prefix.append(contentsOf: scope.utf8)
        prefix.append(quote)
        prefix.append(closeBracket)
        prefix.append(space)

        return scopeRules(css[...], prefix: prefix, depth: 0)
    }

    /// Scope a RULE LIST (top level, or the body of an `@media`/`@supports`): each rule's selector list is
    /// prefixed; nested media/supports recurse; other at-rules + declaration bodies are copied verbatim.
    private static func scopeRules(_ bytes: ArraySlice<UInt8>, prefix: [UInt8], depth: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + prefix.count)
        var index = bytes.startIndex
        var preludeStart = index
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == slash, index + 1 < bytes.endIndex, bytes[index + 1] == star {
                index = skipComment(bytes, from: index)  // stays part of the prelude
            } else if byte == quote || byte == apostrophe {
                index = skipString(bytes, from: index, quote: byte)
            } else if byte == semicolon {
                // An at-statement like `@import …;` (or a stray `;`): copy through, verbatim.
                out.append(contentsOf: bytes[preludeStart ... index])
                index += 1
                preludeStart = index
            } else if byte == openBrace {
                let prelude = bytes[preludeStart ..< index]
                let close = matchingBrace(bytes, openAt: index)
                let inner = bytes[(index + 1) ..< close]
                if startsWithAtRule(prelude, "@media") || startsWithAtRule(prelude, "@supports") {
                    out.append(contentsOf: prelude)
                    out.append(openBrace)
                    out.append(
                        contentsOf: depth < maxNesting
                            ? scopeRules(inner, prefix: prefix, depth: depth + 1) : Array(inner))
                    out.append(closeBrace)
                } else if isAtRulePrelude(prelude) {
                    out.append(contentsOf: prelude)  // @keyframes/@font-face/@page/…: body copied verbatim
                    out.append(openBrace)
                    out.append(contentsOf: inner)
                    out.append(closeBrace)
                } else {
                    out.append(contentsOf: scopeSelectorList(prelude, prefix: prefix))
                    out.append(openBrace)
                    out.append(contentsOf: inner)  // declarations: verbatim
                    out.append(closeBrace)
                }
                index = close + 1
                preludeStart = index
            } else {
                index += 1
            }
        }
        out.append(contentsOf: bytes[preludeStart ..< bytes.endIndex])  // trailing whitespace
        return out
    }

    /// Prefix each top-level (comma-separated) selector, preserving the original whitespace + commas and
    /// skipping any selector that opts out (`:global…` / `.global`).
    private static func scopeSelectorList(_ selectors: ArraySlice<UInt8>, prefix: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var index = selectors.startIndex
        var partStart = index
        var nesting = 0  // `()` / `[]` depth — a comma inside does not split the selector list
        while index < selectors.endIndex {
            let byte = selectors[index]
            if byte == openParen || byte == openBracket {
                nesting += 1
            } else if byte == closeParen || byte == closeBracket {
                if nesting > 0 { nesting -= 1 }
            } else if byte == comma, nesting == 0 {
                out.append(contentsOf: scopeOneSelector(selectors[partStart ..< index], prefix: prefix))
                out.append(comma)
                partStart = index + 1
            }
            index += 1
        }
        out.append(contentsOf: scopeOneSelector(selectors[partStart ..< selectors.endIndex], prefix: prefix))
        return out
    }

    /// Prefix one selector (preserving its leading whitespace), unless it opts out of scoping.
    private static func scopeOneSelector(_ selector: ArraySlice<UInt8>, prefix: [UInt8]) -> [UInt8] {
        guard let firstNonWS = selector.firstIndex(where: { !isWhitespace($0) }) else {
            return Array(selector)  // all whitespace
        }
        let lead = selector[selector.startIndex ..< firstNonWS]
        let body = selector[firstNonWS ..< selector.endIndex]

        if let unwrapped = globalOptOut(body) {
            return Array(lead) + unwrapped  // `:global(…)`/`:global …`/`.global` → unscoped
        }
        return Array(lead) + prefix + Array(body)
    }

    /// `nil` if the selector should be scoped; otherwise the bytes to emit unscoped. Handles the three
    /// opt-out forms: `:global(<sel>)` (unwrap to `<sel>`), `:global <sel>` (drop the keyword), and a
    /// literal `.global` class anywhere in the selector (emit verbatim).
    private static func globalOptOut(_ selector: ArraySlice<UInt8>) -> [UInt8]? {
        if hasPrefix(selector, ":global(") {
            let inner = selector[(selector.startIndex + 8) ..< selector.endIndex]
            if let lastParen = inner.lastIndex(of: closeParen) {
                return Array(inner[inner.startIndex ..< lastParen]) + Array(inner[(lastParen + 1) ..< inner.endIndex])
            }
            return Array(inner)
        }
        if hasPrefix(selector, ":global") { return Array(selector[(selector.startIndex + 7) ..< selector.endIndex]) }
        if contains(selector, ".global") { return Array(selector) }
        return nil
    }

    // MARK: - byte scanning helpers

    /// The index of the `}` that closes the `{` at `openIndex` (brace-balanced, comment-/string-aware). If
    /// unbalanced (malformed author CSS), returns `endIndex - 1` so output stays bounded, never crashes.
    private static func matchingBrace(_ bytes: ArraySlice<UInt8>, openAt openIndex: Int) -> Int {
        var depth = 0
        var index = openIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == slash, index + 1 < bytes.endIndex, bytes[index + 1] == star {
                index = skipComment(bytes, from: index)
                continue
            }
            if byte == quote || byte == apostrophe {
                index = skipString(bytes, from: index, quote: byte)
                continue
            }
            if byte == openBrace {
                depth += 1
            } else if byte == closeBrace {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return bytes.endIndex - 1
    }

    /// Advance past a `/* … */` comment, returning the index just after the closing `*/` (or `endIndex`).
    private static func skipComment(_ bytes: ArraySlice<UInt8>, from start: Int) -> Int {
        var index = start + 2
        while index + 1 < bytes.endIndex {
            if bytes[index] == star, bytes[index + 1] == slash { return index + 2 }
            index += 1
        }
        return bytes.endIndex
    }

    /// Advance past a `"…"` / `'…'` string (honoring `\` escapes), returning the index just after the close.
    private static func skipString(_ bytes: ArraySlice<UInt8>, from start: Int, quote: UInt8) -> Int {
        var index = start + 1
        while index < bytes.endIndex {
            if bytes[index] == backslash {
                index += 2
                continue
            }
            if bytes[index] == quote { return index + 1 }
            index += 1
        }
        return bytes.endIndex
    }

    /// Whether `prelude`, trimmed of leading whitespace, begins with the at-rule keyword `keyword`.
    private static func startsWithAtRule(_ prelude: ArraySlice<UInt8>, _ keyword: StaticString) -> Bool {
        guard let firstNonWS = prelude.firstIndex(where: { !isWhitespace($0) }) else { return false }
        return hasPrefix(prelude[firstNonWS ..< prelude.endIndex], keyword)
    }

    /// Whether the trimmed prelude begins with `@` (any at-rule).
    private static func isAtRulePrelude(_ prelude: ArraySlice<UInt8>) -> Bool {
        guard let firstNonWS = prelude.firstIndex(where: { !isWhitespace($0) }) else { return false }
        return prelude[firstNonWS] == at
    }

    private static func hasPrefix(_ bytes: ArraySlice<UInt8>, _ prefix: StaticString) -> Bool {
        let needle = prefix.withUTF8Buffer { unsafe Array($0) }
        guard bytes.count >= needle.count else { return false }
        var index = bytes.startIndex
        for byte in needle {
            if bytes[index] != byte { return false }
            index += 1
        }
        return true
    }

    private static func contains(_ bytes: ArraySlice<UInt8>, _ needle: StaticString) -> Bool {
        let needleBytes = needle.withUTF8Buffer { unsafe Array($0) }
        guard !needleBytes.isEmpty, bytes.count >= needleBytes.count else { return false }
        var start = bytes.startIndex
        let last = bytes.endIndex - needleBytes.count
        while start <= last {
            var matched = true
            for offset in 0 ..< needleBytes.count where bytes[start + offset] != needleBytes[offset] {
                matched = false
                break
            }
            if matched { return true }
            start += 1
        }
        return false
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == space || byte == tab || byte == newline || byte == carriageReturn
    }

    /// `@media`/`@supports` nesting beyond this is copied verbatim (defense-in-depth; real author CSS never
    /// approaches it). Recursion stays shallow and bounded.
    private static let maxNesting = 8

    // ASCII byte constants (Foundation-free).
    private static let openBrace: UInt8 = 0x7B
    private static let closeBrace: UInt8 = 0x7D
    private static let openParen: UInt8 = 0x28
    private static let closeParen: UInt8 = 0x29
    private static let openBracket: UInt8 = 0x5B
    private static let closeBracket: UInt8 = 0x5D
    private static let comma: UInt8 = 0x2C
    private static let semicolon: UInt8 = 0x3B
    private static let quote: UInt8 = 0x22
    private static let apostrophe: UInt8 = 0x27
    private static let backslash: UInt8 = 0x5C
    private static let slash: UInt8 = 0x2F
    private static let star: UInt8 = 0x2A
    private static let equals: UInt8 = 0x3D
    private static let at: UInt8 = 0x40
    private static let space: UInt8 = 0x20
    private static let tab: UInt8 = 0x09
    private static let newline: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D
}
