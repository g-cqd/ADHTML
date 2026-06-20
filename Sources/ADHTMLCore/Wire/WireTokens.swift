// GENERATED from wire-tokens.json by `swift package generate-wire-tokens` — DO NOT EDIT.
// The closed wire vocabulary (attributes/behaviors/swaps), shared with ClientRuntime/src/tokens.js (parity-tested). 1-char base36 tokens.

/// Generated wire tokens — shared with the JS runtime; do not edit by hand.
public enum WireToken {
    public static let island = "a"
    public static let id = "b"
    public static let on = "c"
    public static let connect = "d"
    public static let bind = "e"
    public static let classToggle = "f"
    public static let show = "g"
    public static let `if` = "h"
    public static let model = "i"
    public static let keys = "j"
    public static let prevent = "k"
    public static let stop = "l"
    public static let each = "m"
    public static let eachText = "n"
    public static let filter = "o"
    public static let action = "p"
    public static let url = "q"
    public static let trigger = "r"
    public static let debounce = "s"
    public static let include = "t"
    public static let target = "u"
    public static let swap = "v"
    public static let optimistic = "w"
    public static let oob = "x"

    /// Every (name, token) pair — the input to the Swift↔JS parity test.
    public static let all: [(name: String, token: String)] = [
        ("island", "a"),
        ("id", "b"),
        ("on", "c"),
        ("connect", "d"),
        ("bind", "e"),
        ("classToggle", "f"),
        ("show", "g"),
        ("if", "h"),
        ("model", "i"),
        ("keys", "j"),
        ("prevent", "k"),
        ("stop", "l"),
        ("each", "m"),
        ("eachText", "n"),
        ("filter", "o"),
        ("action", "p"),
        ("url", "q"),
        ("trigger", "r"),
        ("debounce", "s"),
        ("include", "t"),
        ("target", "u"),
        ("swap", "v"),
        ("optimistic", "w"),
        ("oob", "x")
    ]
}

/// Generated wire tokens — shared with the JS runtime; do not edit by hand.
public enum WireBehavior {
    public static let increment = "a"
    public static let toggle = "b"
    public static let set = "c"
    public static let setFromValue = "d"
    public static let listMove = "e"
    public static let commit = "f"
    public static let removeLast = "g"

    /// Every (name, token) pair — the input to the Swift↔JS parity test.
    public static let all: [(name: String, token: String)] = [
        ("increment", "a"),
        ("toggle", "b"),
        ("set", "c"),
        ("setFromValue", "d"),
        ("listMove", "e"),
        ("commit", "f"),
        ("removeLast", "g")
    ]
}

/// Generated wire tokens — shared with the JS runtime; do not edit by hand.
public enum WireSwap {
    public static let morph = "a"
    public static let innerHTML = "b"
    public static let append = "c"
    public static let outOfBand = "d"

    /// Every (name, token) pair — the input to the Swift↔JS parity test.
    public static let all: [(name: String, token: String)] = [
        ("morph", "a"),
        ("innerHTML", "b"),
        ("append", "c"),
        ("outOfBand", "d")
    ]
}
