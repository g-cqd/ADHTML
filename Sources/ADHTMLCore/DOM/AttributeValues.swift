// Typed values for HTML attributes whose value set is fixed by the spec (ADR-0014). Each is an
// `enum: String` whose `rawValue` is the HTML token; the matching `consuming` modifier forwards to
// `HTMLElement.attribute`, gated exactly like the stringly-typed modifiers (existing trait where one
// exists, per-element `where Tag == Tags.X` otherwise) so compile-time *legality* is preserved and
// compile-time *value validity* is added. Every typed modifier is purely additive: the `String` overload
// in Attributes+Standard.swift stays, so an author-defined / future token is always reachable.

// MARK: - Global enumerated attribute values

/// `dir` — text directionality.
public enum Direction: String, Sendable { case ltr, rtl, auto }

/// `inputmode` — virtual-keyboard hint.
public enum InputMode: String, Sendable { case none, text, decimal, numeric, tel, search, email, url }

/// `enterkeyhint` — the action label of the virtual keyboard's enter key.
public enum EnterKeyHint: String, Sendable { case enter, done, go, next, previous, search, send }

/// `autocapitalize`.
public enum AutoCapitalize: String, Sendable { case off, none, on, sentences, words, characters }

/// `contenteditable` — note this is *enumerated*, not a boolean attribute.
public enum ContentEditable: String, Sendable {
    case `true`, `false`
    case plaintextOnly = "plaintext-only"
}

/// WAI-ARIA `role` (the closed role vocabulary).
public enum Role: String, Sendable {
    case alert, alertdialog, application, article, banner, button, cell, checkbox, columnheader,
        combobox, complementary, contentinfo, definition, dialog, directory, document, feed, figure,
        form, grid, gridcell, group, heading, img, link, list, listbox, listitem, log, main, marquee,
        math, menu, menubar, menuitem, menuitemcheckbox, menuitemradio, navigation, none, note, option,
        presentation, progressbar, radio, radiogroup, region, row, rowgroup, rowheader, scrollbar,
        search, searchbox, separator, slider, spinbutton, status, `switch`, tab, table, tablist,
        tabpanel, term, textbox, timer, toolbar, tooltip, tree, treegrid, treeitem
}

/// `aria-current`.
public enum AriaCurrent: String, Sendable { case page, step, location, date, time, `true`, `false` }
/// `aria-live`.
public enum AriaLive: String, Sendable { case off, polite, assertive }
/// Tri-state for `aria-checked` / `aria-pressed`.
public enum AriaTristate: String, Sendable { case `true`, `false`, mixed }
/// `aria-haspopup`.
public enum AriaHasPopup: String, Sendable { case `false`, `true`, menu, listbox, tree, grid, dialog }

extension HTMLElement {
    /// `dir` (typed).
    public consuming func dir(_ value: Direction) -> Self { attribute("dir", value.rawValue) }
    /// ARIA `role` (typed).
    public consuming func role(_ value: Role) -> Self { attribute("role", value.rawValue) }
    /// `inputmode`.
    public consuming func inputMode(_ value: InputMode) -> Self { attribute("inputmode", value.rawValue) }
    /// `enterkeyhint`.
    public consuming func enterKeyHint(_ value: EnterKeyHint) -> Self { attribute("enterkeyhint", value.rawValue) }
    /// `autocapitalize`.
    public consuming func autocapitalize(_ value: AutoCapitalize) -> Self {
        attribute("autocapitalize", value.rawValue)
    }
    /// `contenteditable` (enumerated; defaults to `true`).
    public consuming func contentEditable(_ value: ContentEditable = .true) -> Self {
        attribute("contenteditable", value.rawValue)
    }
    /// `draggable` (enumerated `true`/`false`, NOT a boolean attribute).
    public consuming func draggable(_ value: Bool) -> Self { attribute("draggable", value ? "true" : "false") }
    /// `spellcheck` (enumerated `true`/`false`).
    public consuming func spellcheck(_ value: Bool) -> Self { attribute("spellcheck", value ? "true" : "false") }
    /// `translate` (`yes`/`no`).
    public consuming func translate(_ on: Bool) -> Self { attribute("translate", on ? "yes" : "no") }
    /// The boolean `inert` attribute (present when `on`).
    public consuming func inert(_ on: Bool = true) -> Self { on ? attribute("inert", "") : self }

    // Typed ARIA states/properties (the first real accessibility surface; ADR-0014).
    /// `aria-label`.
    public consuming func ariaLabel(_ value: String) -> Self { attribute("aria-label", value) }
    /// `aria-hidden`.
    public consuming func ariaHidden(_ value: Bool) -> Self { attribute("aria-hidden", value ? "true" : "false") }
    /// `aria-live`.
    public consuming func ariaLive(_ value: AriaLive) -> Self { attribute("aria-live", value.rawValue) }
    /// `aria-current`.
    public consuming func ariaCurrent(_ value: AriaCurrent) -> Self { attribute("aria-current", value.rawValue) }
    /// `aria-expanded`.
    public consuming func ariaExpanded(_ value: Bool) -> Self { attribute("aria-expanded", value ? "true" : "false") }
    /// `aria-disabled`.
    public consuming func ariaDisabled(_ value: Bool) -> Self { attribute("aria-disabled", value ? "true" : "false") }
    /// `aria-selected`.
    public consuming func ariaSelected(_ value: Bool) -> Self { attribute("aria-selected", value ? "true" : "false") }
    /// `aria-checked` (tri-state).
    public consuming func ariaChecked(_ value: AriaTristate) -> Self { attribute("aria-checked", value.rawValue) }
    /// `aria-pressed` (tri-state).
    public consuming func ariaPressed(_ value: AriaTristate) -> Self { attribute("aria-pressed", value.rawValue) }
    /// `aria-haspopup`.
    public consuming func ariaHasPopup(_ value: AriaHasPopup) -> Self { attribute("aria-haspopup", value.rawValue) }
}

// MARK: - Trait-gated typed values (existing traits)

/// `target` — browsing-context keyword (`_blank`, …) or a named frame.
public enum Target: String, Sendable {
    case `self` = "_self"
    case blank = "_blank"
    case parent = "_parent"
    case top = "_top"
}

/// `rel` — link relationship token (anchor/area/link). Multi-valued: pass several.
public enum Rel: String, Sendable {
    case alternate, author, bookmark, canonical
    case dnsPrefetch = "dns-prefetch"
    case external, help, icon,
        license, manifest, modulepreload, next, nofollow, noopener, noreferrer, pingback, preconnect,
        prefetch, preload, prev, search, stylesheet, tag
}

/// `<form>` `method`.
public enum FormMethod: String, Sendable { case get, post, dialog }

extension HTMLElement where Tag: HasTarget {
    /// `target` (typed keyword).
    public consuming func target(_ value: Target) -> Self { attribute("target", value.rawValue) }
    /// `target` set to a named frame/window.
    public consuming func target(frame name: String) -> Self { attribute("target", name) }
}
extension HTMLElement where Tag: HasRel {
    /// `rel` from one or more typed tokens (space-joined).
    public consuming func rel(_ values: Rel...) -> Self {
        attribute("rel", values.map(\.rawValue).joined(separator: " "))
    }
}
extension HTMLElement where Tag: HasMethod {
    /// `<form>` `method` (typed).
    public consuming func method(_ value: FormMethod) -> Self { attribute("method", value.rawValue) }
}

// MARK: - Per-element `type` (HasType is shared across elements with disjoint value sets)

/// `<input>` `type`.
public enum InputType: String, Sendable {
    case text, search, tel, url, email, password, number, range, color, checkbox, radio, date, time,
        month, week
    case datetimeLocal = "datetime-local"
    case file, hidden, image, button, submit, reset
}
/// `<button>` `type`.
public enum ButtonType: String, Sendable { case submit, reset, button }
/// `<ol>` `type` (marker style).
public enum OrderedListType: String, Sendable {
    case decimal = "1"
    case lowerAlpha = "a"
    case upperAlpha = "A"
    case lowerRoman = "i"
    case upperRoman = "I"
}

extension HTMLElement where Tag == Tags.Input {
    /// `<input type>` (typed).
    public consuming func type(_ value: InputType) -> Self { attribute("type", value.rawValue) }
}
extension HTMLElement where Tag == Tags.Button {
    /// `<button type>` (typed).
    public consuming func type(_ value: ButtonType) -> Self { attribute("type", value.rawValue) }
}
extension HTMLElement where Tag == Tags.Ol {
    /// `<ol type>` (typed marker style).
    public consuming func type(_ value: OrderedListType) -> Self { attribute("type", value.rawValue) }
}

// MARK: - Per-element media/resource attributes (no shared trait — gated per element)

/// `loading` (`<img>`/`<iframe>`).
public enum Loading: String, Sendable { case eager, lazy }
/// `decoding` (`<img>`).
public enum Decoding: String, Sendable { case sync, async, auto }
/// `crossorigin`.
public enum CrossOrigin: String, Sendable {
    case anonymous
    case useCredentials = "use-credentials"
}
/// `referrerpolicy`.
public enum ReferrerPolicy: String, Sendable {
    case noReferrer = "no-referrer"
    case noReferrerWhenDowngrade = "no-referrer-when-downgrade"
    case origin
    case
        originWhenCrossOrigin = "origin-when-cross-origin"
    case sameOrigin = "same-origin"
    case
        strictOrigin = "strict-origin"
    case strictOriginWhenCrossOrigin = "strict-origin-when-cross-origin"
    case
        unsafeURL = "unsafe-url"
}
/// `fetchpriority`.
public enum FetchPriority: String, Sendable { case high, low, auto }
/// `<link as>` — preload destination.
public enum LinkAs: String, Sendable {
    case audio, document, embed, fetch, font, image, object, script, style, track, video, worker
}
/// `<th scope>`.
public enum ColumnScope: String, Sendable { case row, col, rowgroup, colgroup }
/// `<track kind>`.
public enum TrackKind: String, Sendable { case subtitles, captions, descriptions, chapters, metadata }
/// `<textarea wrap>`.
public enum Wrap: String, Sendable { case soft, hard }
/// `<form enctype>`.
public enum Enctype: String, Sendable {
    case urlEncoded = "application/x-www-form-urlencoded"
    case multipart = "multipart/form-data"
    case
        plainText = "text/plain"
}
/// `preload` (`<audio>`/`<video>`).
public enum Preload: String, Sendable { case none, metadata, auto }

extension HTMLElement where Tag == Tags.Img {
    /// `loading`.
    public consuming func loading(_ value: Loading) -> Self { attribute("loading", value.rawValue) }
    /// `decoding`.
    public consuming func decoding(_ value: Decoding) -> Self { attribute("decoding", value.rawValue) }
    /// `crossorigin`.
    public consuming func crossOrigin(_ value: CrossOrigin) -> Self { attribute("crossorigin", value.rawValue) }
    /// `referrerpolicy`.
    public consuming func referrerPolicy(_ value: ReferrerPolicy) -> Self {
        attribute("referrerpolicy", value.rawValue)
    }
    /// `fetchpriority`.
    public consuming func fetchPriority(_ value: FetchPriority) -> Self { attribute("fetchpriority", value.rawValue) }
}
extension HTMLElement where Tag == Tags.Iframe {
    /// `loading`.
    public consuming func loading(_ value: Loading) -> Self { attribute("loading", value.rawValue) }
    /// `referrerpolicy`.
    public consuming func referrerPolicy(_ value: ReferrerPolicy) -> Self {
        attribute("referrerpolicy", value.rawValue)
    }
}
extension HTMLElement where Tag == Tags.Link {
    /// `crossorigin`.
    public consuming func crossOrigin(_ value: CrossOrigin) -> Self { attribute("crossorigin", value.rawValue) }
    /// `referrerpolicy`.
    public consuming func referrerPolicy(_ value: ReferrerPolicy) -> Self {
        attribute("referrerpolicy", value.rawValue)
    }
    /// `fetchpriority`.
    public consuming func fetchPriority(_ value: FetchPriority) -> Self { attribute("fetchpriority", value.rawValue) }
    /// `as` — preload destination.
    public consuming func `as`(_ value: LinkAs) -> Self { attribute("as", value.rawValue) }
}
extension HTMLElement where Tag == Tags.Script {
    /// `crossorigin`.
    public consuming func crossOrigin(_ value: CrossOrigin) -> Self { attribute("crossorigin", value.rawValue) }
    /// `referrerpolicy`.
    public consuming func referrerPolicy(_ value: ReferrerPolicy) -> Self {
        attribute("referrerpolicy", value.rawValue)
    }
    /// `fetchpriority`.
    public consuming func fetchPriority(_ value: FetchPriority) -> Self { attribute("fetchpriority", value.rawValue) }
}
extension HTMLElement where Tag == Tags.A {
    /// `referrerpolicy`.
    public consuming func referrerPolicy(_ value: ReferrerPolicy) -> Self {
        attribute("referrerpolicy", value.rawValue)
    }
}
extension HTMLElement where Tag == Tags.Area {
    /// `referrerpolicy`.
    public consuming func referrerPolicy(_ value: ReferrerPolicy) -> Self {
        attribute("referrerpolicy", value.rawValue)
    }
}
extension HTMLElement where Tag == Tags.Audio {
    /// `crossorigin`.
    public consuming func crossOrigin(_ value: CrossOrigin) -> Self { attribute("crossorigin", value.rawValue) }
    /// `preload`.
    public consuming func preload(_ value: Preload) -> Self { attribute("preload", value.rawValue) }
}
extension HTMLElement where Tag == Tags.Video {
    /// `crossorigin`.
    public consuming func crossOrigin(_ value: CrossOrigin) -> Self { attribute("crossorigin", value.rawValue) }
    /// `preload`.
    public consuming func preload(_ value: Preload) -> Self { attribute("preload", value.rawValue) }
}
extension HTMLElement where Tag == Tags.Th {
    /// `scope`.
    public consuming func scope(_ value: ColumnScope) -> Self { attribute("scope", value.rawValue) }
}
extension HTMLElement where Tag == Tags.Track {
    /// `kind`.
    public consuming func kind(_ value: TrackKind) -> Self { attribute("kind", value.rawValue) }
}
extension HTMLElement where Tag == Tags.Textarea {
    /// `wrap`.
    public consuming func wrap(_ value: Wrap) -> Self { attribute("wrap", value.rawValue) }
}
extension HTMLElement where Tag == Tags.Form {
    /// `enctype`.
    public consuming func enctype(_ value: Enctype) -> Self { attribute("enctype", value.rawValue) }
}

// MARK: - Boolean attribute coverage (present-when-true; mirrors `hidden`/`disabled`)

extension HTMLElement where Tag == Tags.Input {
    public consuming func required(_ on: Bool = true) -> Self { on ? attribute("required", "") : self }
    public consuming func checked(_ on: Bool = true) -> Self { on ? attribute("checked", "") : self }
    public consuming func readOnly(_ on: Bool = true) -> Self { on ? attribute("readonly", "") : self }
    public consuming func multiple(_ on: Bool = true) -> Self { on ? attribute("multiple", "") : self }
    public consuming func autoFocus(_ on: Bool = true) -> Self { on ? attribute("autofocus", "") : self }
}
extension HTMLElement where Tag == Tags.Textarea {
    public consuming func required(_ on: Bool = true) -> Self { on ? attribute("required", "") : self }
    public consuming func readOnly(_ on: Bool = true) -> Self { on ? attribute("readonly", "") : self }
}
extension HTMLElement where Tag == Tags.Select {
    public consuming func required(_ on: Bool = true) -> Self { on ? attribute("required", "") : self }
    public consuming func multiple(_ on: Bool = true) -> Self { on ? attribute("multiple", "") : self }
}
extension HTMLElement where Tag == Tags.Option {
    public consuming func selected(_ on: Bool = true) -> Self { on ? attribute("selected", "") : self }
}
extension HTMLElement where Tag == Tags.Details {
    public consuming func open(_ on: Bool = true) -> Self { on ? attribute("open", "") : self }
}
extension HTMLElement where Tag == Tags.Dialog {
    public consuming func open(_ on: Bool = true) -> Self { on ? attribute("open", "") : self }
}
extension HTMLElement where Tag == Tags.Form {
    public consuming func noValidate(_ on: Bool = true) -> Self { on ? attribute("novalidate", "") : self }
}
extension HTMLElement where Tag == Tags.Script {
    public consuming func async(_ on: Bool = true) -> Self { on ? attribute("async", "") : self }
    public consuming func `defer`(_ on: Bool = true) -> Self { on ? attribute("defer", "") : self }
}
extension HTMLElement where Tag == Tags.Audio {
    public consuming func controls(_ on: Bool = true) -> Self { on ? attribute("controls", "") : self }
    public consuming func loop(_ on: Bool = true) -> Self { on ? attribute("loop", "") : self }
    public consuming func muted(_ on: Bool = true) -> Self { on ? attribute("muted", "") : self }
    public consuming func autoplay(_ on: Bool = true) -> Self { on ? attribute("autoplay", "") : self }
}
extension HTMLElement where Tag == Tags.Video {
    public consuming func controls(_ on: Bool = true) -> Self { on ? attribute("controls", "") : self }
    public consuming func loop(_ on: Bool = true) -> Self { on ? attribute("loop", "") : self }
    public consuming func muted(_ on: Bool = true) -> Self { on ? attribute("muted", "") : self }
    public consuming func autoplay(_ on: Bool = true) -> Self { on ? attribute("autoplay", "") : self }
    public consuming func playsInline(_ on: Bool = true) -> Self { on ? attribute("playsinline", "") : self }
}
