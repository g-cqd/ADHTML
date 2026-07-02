/// The common named character references (the full ~2200-entry WHATWG table is a follow-up; these
/// cover Apple developer-doc HTML). PURE DATA shared by two independent decoders: the shipping
/// `HTMLTape.decodeReference` and the `ADHTMLOracle` reference tokenizer (hence `package`, not
/// internal). Sharing the table does not weaken the differential tests — the two decode *logics*
/// stay independent; only the name→replacement mapping (which must be identical by definition,
/// it's the spec's data) has a single source of truth.
package let namedCharacterReferences: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}",
    "copy": "\u{A9}", "reg": "\u{AE}", "trade": "\u{2122}", "hellip": "\u{2026}",
    "mdash": "\u{2014}", "ndash": "\u{2013}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
    "ldquo": "\u{201C}", "rdquo": "\u{201D}", "middot": "\u{B7}", "bull": "\u{2022}",
    "deg": "\u{B0}", "times": "\u{D7}", "divide": "\u{F7}", "frac12": "\u{BD}",
    "laquo": "\u{AB}", "raquo": "\u{BB}", "rarr": "\u{2192}", "larr": "\u{2190}",
    "harr": "\u{2194}", "hearts": "\u{2665}", "check": "\u{2713}", "cross": "\u{2717}"
]
