// ADHTMLCodegen — the element/attribute table generator (ADR-0009). It emits the `Tags` phantom-tag
// enum (names + void-ness + trait conformances) and the lowercase element-constructor functions for the
// full standard HTML element set, from the single curated spec below. Run it MANUALLY and commit the
// output — it is deliberately NOT a build plugin, so consumers never run codegen and the generated
// surface is reviewable in diffs:
//
//     swift run ADHTMLCodegen            # writes into Sources/ADHTMLCore/DOM/Generated/
//     swift run ADHTMLCodegen <out-dir>  # or a custom directory
//     swift format --in-place --configuration .swift-format --recursive Sources/ADHTMLCore/DOM/Generated
//
// The trait PROTOCOLS (HasHref, HasSrc, …) and their attribute modifiers stay hand-written (Traits.swift
// / Attributes+Standard.swift) — they pair compile-time attribute legality with escaping context, which
// is a design choice, not a mechanical mapping. This tool only assigns each element to the traits it may
// legally carry. The hybrid model (ADR-0009): global attributes apply everywhere; ~14 traits gate the
// high-value element-specific attributes, avoiding a combinatorial attribute explosion.

import Foundation

/// One row of the element table: the HTML tag name, whether it is a void element (no children, no close
/// tag), and the attribute traits it may carry.
struct Element {
    let html: String
    var void = false
    var traits: [String] = []
}

/// A named, ordered group of elements (mirrors the MDN element categories) for readable output.
struct Group {
    let title: String
    let elements: [Element]
}

// MARK: - The spec

let groups: [Group] = [
    Group(
        title: "Main root & document metadata",
        elements: [
            Element(html: "html"),
            Element(html: "head"),
            Element(html: "title"),
            Element(html: "base", void: true, traits: ["HasHref", "HasTarget"]),
            Element(html: "link", void: true, traits: ["HasHref", "HasRel", "HasType"]),
            Element(html: "meta", void: true, traits: ["HasName", "HasContent"]),
            Element(html: "style", traits: ["HasType"]),
            Element(html: "body")
        ]),
    Group(
        title: "Content sectioning",
        elements: [
            Element(html: "address"),
            Element(html: "article"),
            Element(html: "aside"),
            Element(html: "footer"),
            Element(html: "header"),
            Element(html: "hgroup"),
            Element(html: "h1"), Element(html: "h2"), Element(html: "h3"),
            Element(html: "h4"), Element(html: "h5"), Element(html: "h6"),
            Element(html: "main"),
            Element(html: "nav"),
            Element(html: "section"),
            Element(html: "search")
        ]),
    Group(
        title: "Text content",
        elements: [
            Element(html: "blockquote"),
            Element(html: "dd"),
            Element(html: "div"),
            Element(html: "dl"),
            Element(html: "dt"),
            Element(html: "figcaption"),
            Element(html: "figure"),
            Element(html: "hr", void: true),
            Element(html: "li", traits: ["HasValue"]),
            Element(html: "menu"),
            Element(html: "ol", traits: ["HasType"]),
            Element(html: "p"),
            Element(html: "pre"),
            Element(html: "ul")
        ]),
    Group(
        title: "Inline text semantics",
        elements: [
            Element(html: "a", traits: ["HasHref", "HasRel", "HasTarget"]),
            Element(html: "abbr"),
            Element(html: "b"),
            Element(html: "bdi"),
            Element(html: "bdo"),
            Element(html: "br", void: true),
            Element(html: "cite"),
            Element(html: "code"),
            Element(html: "data", traits: ["HasValue"]),
            Element(html: "dfn"),
            Element(html: "em"),
            Element(html: "i"),
            Element(html: "kbd"),
            Element(html: "mark"),
            Element(html: "q"),
            Element(html: "rp"),
            Element(html: "rt"),
            Element(html: "ruby"),
            Element(html: "s"),
            Element(html: "samp"),
            Element(html: "small"),
            Element(html: "span"),
            Element(html: "strong"),
            Element(html: "sub"),
            Element(html: "sup"),
            Element(html: "time"),
            Element(html: "u"),
            Element(html: "var"),
            Element(html: "wbr", void: true)
        ]),
    Group(
        title: "Image & multimedia",
        elements: [
            Element(html: "area", void: true, traits: ["HasHref", "HasAlt", "HasRel", "HasTarget"]),
            Element(html: "audio", traits: ["HasSrc"]),
            Element(html: "img", void: true, traits: ["HasSrc", "HasAlt"]),
            Element(html: "map", traits: ["HasName"]),
            Element(html: "track", void: true, traits: ["HasSrc"]),
            Element(html: "video", traits: ["HasSrc"])
        ]),
    Group(
        title: "Embedded content",
        elements: [
            Element(html: "embed", void: true, traits: ["HasSrc", "HasType"]),
            Element(html: "iframe", traits: ["HasSrc", "HasName"]),
            Element(html: "object", traits: ["HasType", "HasName"]),
            Element(html: "picture"),
            Element(html: "source", void: true, traits: ["HasSrc", "HasType"])
        ]),
    Group(
        title: "Scripting",
        elements: [
            Element(html: "canvas"),
            Element(html: "noscript"),
            Element(html: "script", traits: ["HasSrc", "HasType"])
        ]),
    Group(
        title: "Demarcating edits",
        elements: [
            Element(html: "del"),
            Element(html: "ins")
        ]),
    Group(
        title: "Table content",
        elements: [
            Element(html: "caption"),
            Element(html: "col", void: true),
            Element(html: "colgroup"),
            Element(html: "table"),
            Element(html: "tbody"),
            Element(html: "td"),
            Element(html: "tfoot"),
            Element(html: "th"),
            Element(html: "thead"),
            Element(html: "tr")
        ]),
    Group(
        title: "Forms",
        elements: [
            Element(html: "button", traits: ["HasType", "HasName", "HasValue", "HasDisabled"]),
            Element(html: "datalist"),
            Element(html: "fieldset", traits: ["HasName", "HasDisabled"]),
            Element(html: "form", traits: ["HasName", "HasAction", "HasMethod", "HasTarget"]),
            Element(
                html: "input", void: true,
                traits: ["HasSrc", "HasType", "HasName", "HasValue", "HasPlaceholder", "HasDisabled", "HasAlt"]),
            Element(html: "label", traits: ["HasFor"]),
            Element(html: "legend"),
            Element(html: "meter", traits: ["HasValue"]),
            Element(html: "optgroup", traits: ["HasDisabled"]),
            Element(html: "option", traits: ["HasValue", "HasDisabled"]),
            Element(html: "output", traits: ["HasFor", "HasName"]),
            Element(html: "progress", traits: ["HasValue"]),
            Element(html: "select", traits: ["HasName", "HasDisabled"]),
            Element(html: "textarea", traits: ["HasName", "HasPlaceholder", "HasDisabled"])
        ]),
    Group(
        title: "Interactive elements",
        elements: [
            Element(html: "details", traits: ["HasName"]),
            Element(html: "dialog"),
            Element(html: "summary")
        ]),
    Group(
        title: "Web components",
        elements: [
            Element(html: "slot", traits: ["HasName"]),
            Element(html: "template")
        ])
]

// MARK: - Name mapping

/// Swift keywords that are also HTML element names — the constructor function must backtick them.
let swiftKeywords: Set<String> = [
    "var", "func", "class", "struct", "enum", "protocol", "for", "in", "if", "else", "switch", "case",
    "default", "while", "repeat", "do", "return", "break", "continue", "is", "as", "self", "init", "let",
    "guard", "defer", "throw", "try", "catch", "import", "extension", "typealias", "where", "operator"
]

/// The phantom-tag type name: the HTML name with an uppercased first character (`div`→`Div`, `h1`→`H1`).
func typeName(_ html: String) -> String {
    guard let first = html.first else { return html }
    return first.uppercased() + html.dropFirst()
}

/// The constructor function name: the HTML name, backticked if it collides with a Swift keyword.
func functionName(_ html: String) -> String {
    swiftKeywords.contains(html) ? "`\(html)`" : html
}

// MARK: - Emit

let header = """
    // GENERATED by ADHTMLCodegen — do not edit by hand.
    // Regenerate: `swift run ADHTMLCodegen` then `swift format --in-place …` (see Sources/ADHTMLCodegen).

    """

func emitTags() -> String {
    var out = header
    out += """

        // The phantom-tag namespace: every standard HTML element as a zero-size type carrying its name,
        // void-ness, and the attribute traits it may legally carry (ADR-0009). The DSL surface is the
        // lowercase element functions (Elements.swift); callers never write these type names directly.
        public enum Tags {

        """
    for group in groups {
        out += "    // MARK: \(group.title)\n"
        for element in group.elements {
            let conformances = element.traits.isEmpty ? ["HTMLTag"] : element.traits
            let inherit = conformances.joined(separator: ", ")
            if element.void {
                out += """
                        public enum \(typeName(element.html)): \(inherit) {
                            public static let openMarkup: StaticString = "<\(element.html)"
                            public static let closeMarkup: StaticString = "</\(element.html)>"
                            public static let isVoid = true
                        }

                    """
            } else {
                out += """
                        public enum \(typeName(element.html)): \(inherit) {
                            public static let openMarkup: StaticString = "<\(element.html)"
                            public static let closeMarkup: StaticString = "</\(element.html)>"
                        }

                    """
            }
        }
        out += "\n"
    }
    out += "}\n"
    return out
}

func emitElements() -> String {
    var out = header
    out += """

        // Lowercase element constructors — the DSL surface. Paired elements take `@HTMLBuilder` content;
        // void elements take none. Attribute legality (`.href`, `.src`, …) is gated by each tag's traits.

        """
    for group in groups {
        out += "// MARK: \(group.title)\n\n"
        for element in group.elements {
            let type = "Tags.\(typeName(element.html))"
            let name = functionName(element.html)
            if element.void {
                out += """
                    @inlinable public func \(name)() -> HTMLElement<\(type), EmptyHTML> {
                        HTMLElement(content: EmptyHTML())
                    }

                    """
            } else {
                out += """
                    @inlinable public func \(name)<Content: HTML>(@HTMLBuilder _ content: () -> Content) -> HTMLElement<
                        \(type), Content
                    > {
                        HTMLElement(content: content())
                    }

                    """
            }
        }
    }
    return out
}

// MARK: - Write

let outDir =
    CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/ADHTMLCore/DOM/Generated"

let fileManager = FileManager.default
try fileManager.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let tagsURL = URL(fileURLWithPath: outDir).appendingPathComponent("Tags.swift")
let elementsURL = URL(fileURLWithPath: outDir).appendingPathComponent("Elements.swift")
try emitTags().write(to: tagsURL, atomically: true, encoding: .utf8)
try emitElements().write(to: elementsURL, atomically: true, encoding: .utf8)

let total = groups.reduce(0) { $0 + $1.elements.count }
print("ADHTMLCodegen: wrote \(total) elements to \(tagsURL.path) and \(elementsURL.path)")
