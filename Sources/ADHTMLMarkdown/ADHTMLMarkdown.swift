// ADHTMLMarkdown (gated `ADHTML_MARKDOWN`) — render swift-markdown's AST into ADHTML nodes (we own the
// HTML renderer). Placeholder this pass; kept gated because swift-markdown is a C (cmark-gfm)
// dependency (ADR-0010/0011).
internal import ADHTMLCore

/// Namespace for the Markdown → ADHTML renderer.
public enum ADHTMLMarkdown {}
