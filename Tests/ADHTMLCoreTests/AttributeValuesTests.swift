import Testing

@testable import ADHTMLCore

struct AttributeValuesTests {
    @Test
    func `typed target, rel (multi), and form method render their tokens`() {
        #expect(
            a { "x" }.href("/").target(.blank).rel(.noopener, .noreferrer).render()
                == #"<a href="/" target="_blank" rel="noopener noreferrer">x</a>"#
        )
        #expect(
            form { input().name("q") }.method(.post).enctype(.multipart).render()
                == #"<form method="post" enctype="multipart/form-data"><input name="q"></form>"#
        )
        #expect(a { "x" }.target(frame: "main").render() == #"<a target="main">x</a>"#)
    }

    @Test
    func `per-element type overloads carry disjoint value sets`() {
        #expect(input().type(.email).render() == #"<input type="email">"#)
        #expect(input().type(.datetimeLocal).render() == #"<input type="datetime-local">"#)
        #expect(button { "Go" }.type(.submit).render() == #"<button type="submit">Go</button>"#)
        #expect(ol { li { "a" } }.type(.upperRoman).render() == #"<ol type="I"><li>a</li></ol>"#)
    }

    @Test
    func `media and resource attributes are typed`() {
        #expect(
            img().src("/a.png").alt("a").loading(.lazy).decoding(.async).fetchPriority(.high).render()
                == #"<img src="/a.png" alt="a" loading="lazy" decoding="async" fetchpriority="high">"#
        )
        #expect(
            link().rel(.preload).href("/f.woff2").as(.font).crossOrigin(.anonymous).render()
                == #"<link rel="preload" href="/f.woff2" as="font" crossorigin="anonymous">"#
        )
    }

    @Test
    func `boolean modifiers are present-when-true and omitted otherwise`() {
        #expect(
            input().type(.checkbox).checked().required().render()
                == #"<input type="checkbox" checked="" required="">"#
        )
        #expect(input().checked(false).required(false).render() == "<input>")
        #expect(details { "x" }.open().render() == #"<details open="">x</details>"#)
        #expect(option { "A" }.value("a").selected().render() == #"<option value="a" selected="">A</option>"#)
    }

    // B5 — presence attributes both-polarity + independent. Each emits ITS OWN name, only when true: a
    // mutation mapping one to another's name, or making a present-when-true attribute unconditional, fails
    // here. Split across small bodies so each type-checks under the timing gate.
    @Test
    func `input presence attributes are present-when-true, absent-when-false`() {
        #expect(input().readOnly().render() == #"<input readonly="">"#)
        #expect(input().readOnly(false).render() == "<input>")
        #expect(input().autoFocus().render() == #"<input autofocus="">"#)
        #expect(input().autoFocus(false).render() == "<input>")
        #expect(input().disabled(false).render() == "<input>")
    }

    @Test
    func `container presence attributes are present-when-true, absent-when-false`() {
        #expect(select { "x" }.multiple().render() == #"<select multiple="">x</select>"#)
        #expect(select { "x" }.multiple(false).render() == #"<select>x</select>"#)
        #expect(option { "A" }.selected(false).render() == #"<option>A</option>"#)
        #expect(form {}.noValidate().render() == #"<form novalidate=""></form>"#)
        #expect(form {}.noValidate(false).render() == "<form></form>")
    }

    @Test
    func `global presence attributes are present-when-true, absent-when-false`() {
        #expect(details { "x" }.open(false).render() == #"<details>x</details>"#)
        #expect(span { "x" }.hidden(false).render() == "<span>x</span>")
        #expect(div { "x" }.inert().render() == #"<div inert="">x</div>"#)
        #expect(div { "x" }.inert(false).render() == #"<div>x</div>"#)
    }

    @Test
    func `typed ARIA renders roles and states`() {
        #expect(
            div { "x" }.role(.navigation).ariaLive(.polite).ariaHidden(false).render()
                == #"<div role="navigation" aria-live="polite" aria-hidden="false">x</div>"#
        )
        #expect(
            button { "Menu" }.ariaHasPopup(.menu).ariaExpanded(false).render()
                == #"<button aria-haspopup="menu" aria-expanded="false">Menu</button>"#
        )
    }

    @Test
    func `enumerated globals that look boolean render true or false`() {
        #expect(
            div { "x" }.draggable(true).contentEditable().spellcheck(false).render()
                == #"<div draggable="true" contenteditable="true" spellcheck="false">x</div>"#
        )
    }

    @Test
    func `the String escape hatch still works alongside the typed overloads`() {
        #expect(a { "x" }.target("_top").rel("license").render() == #"<a target="_top" rel="license">x</a>"#)
        #expect(div { "x" }.role("custom-role").render() == #"<div role="custom-role">x</div>"#)
        #expect(input().type("week").render() == #"<input type="week">"#)
    }
}
