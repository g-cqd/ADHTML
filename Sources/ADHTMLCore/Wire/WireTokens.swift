// GENERATED from wire-tokens.json by `swift package generate-wire-tokens` — DO NOT EDIT.
// The closed wire vocabulary (attributes/behaviors/swaps), shared with ClientRuntime/src/tokens.js (parity-tested). 1-char base36 tokens.

/// Generated wire tokens — shared with the JS runtime; do not edit by hand.
public enum WireToken {
    public static let island = "data-a"
    public static let id = "data-b"
    public static let on = "data-c"
    public static let connect = "data-d"
    public static let bind = "data-e"
    public static let classToggle = "data-f"
    public static let show = "data-g"
    public static let `if` = "data-h"
    public static let model = "data-i"
    public static let keys = "data-j"
    public static let prevent = "data-k"
    public static let stop = "data-l"
    public static let each = "data-m"
    public static let eachText = "data-n"
    public static let filter = "data-o"
    public static let action = "data-p"
    public static let url = "data-q"
    public static let trigger = "data-r"
    public static let debounce = "data-s"
    public static let include = "data-t"
    public static let target = "data-u"
    public static let swap = "data-v"
    public static let optimistic = "data-w"
    public static let oob = "data-x"
    public static let keymap = "data-y"
    public static let link = "data-z"
    public static let component = "data-0"
    public static let scope = "data-1"

    /// Every (name, token) pair — the input to the Swift↔JS parity test.
    public static let all: [(name: String, token: String)] = [
        ("island", "data-a"),
        ("id", "data-b"),
        ("on", "data-c"),
        ("connect", "data-d"),
        ("bind", "data-e"),
        ("classToggle", "data-f"),
        ("show", "data-g"),
        ("if", "data-h"),
        ("model", "data-i"),
        ("keys", "data-j"),
        ("prevent", "data-k"),
        ("stop", "data-l"),
        ("each", "data-m"),
        ("eachText", "data-n"),
        ("filter", "data-o"),
        ("action", "data-p"),
        ("url", "data-q"),
        ("trigger", "data-r"),
        ("debounce", "data-s"),
        ("include", "data-t"),
        ("target", "data-u"),
        ("swap", "data-v"),
        ("optimistic", "data-w"),
        ("oob", "data-x"),
        ("keymap", "data-y"),
        ("link", "data-z"),
        ("component", "data-0"),
        ("scope", "data-1")
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
    public static let commitValue = "h"

    /// Every (name, token) pair — the input to the Swift↔JS parity test.
    public static let all: [(name: String, token: String)] = [
        ("increment", "a"),
        ("toggle", "b"),
        ("set", "c"),
        ("setFromValue", "d"),
        ("listMove", "e"),
        ("commit", "f"),
        ("removeLast", "g"),
        ("commitValue", "h")
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
