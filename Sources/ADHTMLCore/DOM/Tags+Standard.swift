// A standard set of HTML elements beyond the Tier-C bootstrap subset, plus the trait protocols that
// gate element-specific attributes (ADR-0009's hybrid model: global attributes apply everywhere;
// these traits restrict element-specific attributes — e.g. `.src` only compiles on a tag conforming to
// `HasSrc`). This set is hand-curated for the common case; the full WHATWG table is a codegen follow-up.

public protocol HasSrc: HTMLTag {}
public protocol HasType: HTMLTag {}
public protocol HasName: HTMLTag {}
public protocol HasValue: HTMLTag {}
public protocol HasPlaceholder: HTMLTag {}
public protocol HasFor: HTMLTag {}
public protocol HasDisabled: HTMLTag {}
public protocol HasAlt: HTMLTag {}
public protocol HasRel: HTMLTag {}

extension Tags {
    // Document
    public enum Html: HTMLTag { public static let name: StaticString = "html" }
    public enum Head: HTMLTag { public static let name: StaticString = "head" }
    public enum Body: HTMLTag { public static let name: StaticString = "body" }
    public enum Title: HTMLTag { public static let name: StaticString = "title" }
    public enum Style: HasType { public static let name: StaticString = "style" }
    public enum Script: HasSrc, HasType { public static let name: StaticString = "script" }
    public enum Meta: HTMLTag {
        public static let name: StaticString = "meta"
        public static let isVoid = true
    }
    public enum Link: HasHref, HasRel, HasType {
        public static let name: StaticString = "link"
        public static let isVoid = true
    }

    // Headings
    public enum H1: HTMLTag { public static let name: StaticString = "h1" }
    public enum H2: HTMLTag { public static let name: StaticString = "h2" }
    public enum H3: HTMLTag { public static let name: StaticString = "h3" }
    public enum H4: HTMLTag { public static let name: StaticString = "h4" }
    public enum H5: HTMLTag { public static let name: StaticString = "h5" }
    public enum H6: HTMLTag { public static let name: StaticString = "h6" }

    // Sectioning
    public enum Nav: HTMLTag { public static let name: StaticString = "nav" }
    public enum Header: HTMLTag { public static let name: StaticString = "header" }
    public enum Footer: HTMLTag { public static let name: StaticString = "footer" }
    public enum Main: HTMLTag { public static let name: StaticString = "main" }
    public enum Section: HTMLTag { public static let name: StaticString = "section" }
    public enum Article: HTMLTag { public static let name: StaticString = "article" }

    // Lists
    public enum Ul: HTMLTag { public static let name: StaticString = "ul" }
    public enum Ol: HTMLTag { public static let name: StaticString = "ol" }
    public enum Li: HTMLTag { public static let name: StaticString = "li" }

    // Inline / text
    public enum Strong: HTMLTag { public static let name: StaticString = "strong" }
    public enum Em: HTMLTag { public static let name: StaticString = "em" }
    public enum Code: HTMLTag { public static let name: StaticString = "code" }
    public enum Pre: HTMLTag { public static let name: StaticString = "pre" }
    public enum Label: HasFor { public static let name: StaticString = "label" }

    // Forms
    public enum Form: HasName { public static let name: StaticString = "form" }
    public enum Textarea: HasName, HasPlaceholder, HasDisabled {
        public static let name: StaticString = "textarea"
    }
    public enum Select: HasName, HasDisabled { public static let name: StaticString = "select" }
    public enum Option: HasValue { public static let name: StaticString = "option" }
    public enum Input: HasSrc, HasType, HasName, HasValue, HasPlaceholder, HasDisabled {
        public static let name: StaticString = "input"
        public static let isVoid = true
    }

    // Media / misc
    public enum Img: HasSrc, HasAlt {
        public static let name: StaticString = "img"
        public static let isVoid = true
    }
    public enum Hr: HTMLTag {
        public static let name: StaticString = "hr"
        public static let isVoid = true
    }
}
