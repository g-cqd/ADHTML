# ADR 0003 — Escape-by-default + context-aware escaping

- **Status**: Proposed
- **Date**: 2026-06-19
- **Related**: RFC-0002, RFC-0003; ADR-0011 (ADFCore reuse). OWASP A03 Injection; CWE-79 (XSS, #1 on the 2025 CWE Top 25)

## Context

XSS is the single most common web vulnerability. Elementary escapes by default but distinguishes only
*text* vs *attribute* contexts — it does not specially defend `href`/`src` URLs, `<script>`/`<style>`
bodies, or JSON embedded in `<script>`. ADHTML embeds a JSON state graph in a `<script>` (RFC-0003),
so a script/JSON-breakout defense is mandatory, not optional. HTMLKit demonstrates the right model: an
`EscapeContext` taint type.

## Decision

Output encoding is **escape-by-default and context-aware**. `EscapeContext { text, attribute, url,
css, scriptJSON }` is chosen by the element/attribute *type*, not the author:

- **text** — escape `& < >`;
- **attribute** — escape `& < > " '`;
- **url** (`href`/`src`) — **scheme allowlist** (reject `javascript:`/`data:` and obfuscations) then
  percent-encode (`ADFCore.PercentCoding`);
- **css** — CSS-string escape or refuse interpolation;
- **scriptJSON** — JSON (via `ADJSON`) with `</`→`<\/` and U+2028/U+2029 escaped (no `</script>`
  breakout).

Escapers are byte transforms built on `ADFCore` primitives (`ASCII`, `PercentCoding`, `UTF8Validation`
— ADR-0011). The **only** unescaped path is `RawHTML(unsafelyEscaped:)` — a single, conspicuously
named, greppable hatch. Escaping logic is **fuzzed** (`ADHTMLFuzz`) with the round-trip invariant that
escaped output never introduces an element/attribute/script boundary absent from the input, plus an
OWASP XSS-vector corpus that must render inert.

## Consequences

- **Positive**: XSS-safe *by construction* — the author cannot place unescaped bytes except via the
  one greppable hatch; review and audit are tractable; the JSON-embed channel needed by hydration is
  safe by design.
- **Negative**: Tier-C ships `text`/`attribute` first and routes `url`/`css`/`scriptJSON` through the
  conservative attribute escaper as a *fail-safe* stub (over-escape, never under-escape) until their
  full encoders land — stated honestly so the gap is visible.
- Escaping is on the hot path; the byte-scan loop copies safe runs verbatim and emits entities only for
  the rare escapable byte (perf-gated by the ordo-one escaper benchmark).
