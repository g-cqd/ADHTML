// Attribute-trait protocols (ADR-0009). Each marks the tags that may legally carry one element-specific
// attribute; the matching modifier (Attributes+Standard.swift) is offered only where `Tag` conforms, so
// e.g. `.href` on a `<div>` is a compile error rather than invalid HTML at runtime. The generator
// (ADHTMLCodegen) assigns elements to these traits; the protocols + modifiers are hand-written because
// each binds a legality rule to an escaping context (URLs are scheme-allowlisted, etc.).

/// Tags that may carry `href` (`<a>`, `<area>`, `<link>`, `<base>`).
public protocol HasHref: HTMLTag {}
/// Tags that may carry `src` (`<img>`, `<script>`, `<iframe>`, media, `<input>`, …).
public protocol HasSrc: HTMLTag {}
/// Tags that may carry `type` (`<input>`, `<button>`, `<script>`, `<style>`, `<link>`, `<ol>`, …).
public protocol HasType: HTMLTag {}
/// Tags that may carry `name` (form controls, `<form>`, `<iframe>`, `<meta>`, `<slot>`, …).
public protocol HasName: HTMLTag {}
/// Tags that may carry `value` (`<input>`, `<option>`, `<button>`, `<li>`, `<meter>`, `<progress>`, …).
public protocol HasValue: HTMLTag {}
/// Tags that may carry `placeholder` (`<input>`, `<textarea>`).
public protocol HasPlaceholder: HTMLTag {}
/// Tags that may carry `for` (`<label>`, `<output>`).
public protocol HasFor: HTMLTag {}
/// Tags that may carry the boolean `disabled` (form controls).
public protocol HasDisabled: HTMLTag {}
/// Tags that may carry `alt` (`<img>`, `<area>`, `<input type=image>`).
public protocol HasAlt: HTMLTag {}
/// Tags that may carry `rel` (`<a>`, `<area>`, `<link>`).
public protocol HasRel: HTMLTag {}
/// Tags that may carry `target` (`<a>`, `<area>`, `<base>`, `<form>`).
public protocol HasTarget: HTMLTag {}
/// Tags that may carry `content` (`<meta>`).
public protocol HasContent: HTMLTag {}
/// Tags that may carry `action` (`<form>`).
public protocol HasAction: HTMLTag {}
/// Tags that may carry `method` (`<form>`).
public protocol HasMethod: HTMLTag {}
