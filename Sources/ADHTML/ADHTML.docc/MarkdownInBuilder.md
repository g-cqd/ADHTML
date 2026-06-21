# Markdown in a Component Body

Write Markdown as a Swift string — or a result builder — and embed live, fully-hydrated components in the
prose.

## Overview

The gated `ADHTMLMarkdown` product lets you author Markdown inside a component body and **embed ADHTML
components in the text**, rendered to escape-by-default HTML with full hydration intact. It builds on
`ADHTMLMarkdown.render` — a pure CommonMark + GFM renderer that routes every text, attribute, and URL through
the engine's escaper, so untrusted Markdown can't inject markup.

Enable the gate when resolving/building:

```sh
ADHTML_MARKDOWN=1 swift build --build-system native
```

```swift
import ADHTML
import ADHTMLMarkdown
```

## The string form

`Markdown(_:)` takes a string literal with **typed** interpolations — it reads like a template literal:

```swift
Markdown("""
# \(title)

In stock: **\(qty)** units.

Buy: \(BuyButton(sku: sku))
""")
```

The interpolations are:

| Interpolation | Meaning |
|---|---|
| `\(component)` | embed a live `some HTML` (rendered + hydrated in place) |
| `\(optional)` | a `C?` — embeds the component, or nothing when `nil` |
| `\(text: string)` | an **untrusted** string as escaped Markdown text (the safe default) |
| `\(url: string)` | a sanitized link/image destination |

There is deliberately **no** bare `\(string)` interpolation: a `String` is not `HTML`, so `\(userInput)`
fails to compile. Untrusted text must go through `\(text:)`, which closes the injection footgun.

## The builder form

`Markdown { … }` with the `@MarkdownBuilder` adds control flow the string form can't express. Statements are
author-trusted Markdown `String` fragments and `some HTML` components; fragments join with a newline:

```swift
Markdown {
    "# \(product.name)"
    if product.isHot { Badge("HOT") }
    "## Specs"
    for spec in product.specs {
        "- **\(spec.key):** \(spec.value)"
    }
    AddToCart(sku: product.sku)   // a live interactive island, inline in the prose
}
```

`if` / `else` / `for` / optionals all work via the builder.

## Full hydration fidelity

An embedded component is not flattened to static text — it renders exactly as if placed directly in the body.
On the hydratable path, an embedded `@State` / `@Component` island's hydration markup lands in the page
program where the island scan finds it, so it appears in the inline state with its own scoped cells and wires
normally. Delegated actions (the `data-adh-*` attributes) are attribute-only, so they survive intact. On the
static path, an embedded component renders inline (no island), matching static semantics.

This works because each embedded slot is captured as a *target-generic render thunk* — the component's
concrete type is baked into a closure rendered into whatever target the Markdown is rendered into — so a
heterogeneous mix of components never has to become `any HTML`.

## How embedding stays safe

Under the hood, each slot is planted in the Markdown source as a Private-Use-Area sentinel scalar
(`U+E000 + index`). These scalars **survive the escaper** (it only rewrites the five ASCII HTML bytes), so the
source renders once, the resulting HTML is split on the sentinels, and each slot is spliced in. The only
`raw` bytes emitted are (a) the renderer's already-escaped output and (b) the component's already
engine-rendered output, so:

- a hostile Markdown string can't break out around a slot — the segments are balanced, escaped renderer
  output;
- `\(text:)` is escaped as literal Markdown text, and the renderer HTML-escapes `<` `>` `&` `"` `'`;
- `\(url:)` is neutralized and the renderer's URL context allowlists schemes, so `[x](javascript:…)` is
  inert;
- author-typed Private-Use-Area scalars are sanitized, so only engine-planted sentinels exist — the sentinel
  never leaks into the output.

`allowRawHTML` (off by default) is orthogonal to slots: it controls whether *raw HTML in the Markdown source*
is passed through or escaped; embedded components render either way.

> Note: a component inside a Markdown code span/block is not supported; a block component alone in its own
> paragraph is unwrapped from the `<p>` the renderer would otherwise wrap it in. Nested `Markdown` works by
> recursion.
