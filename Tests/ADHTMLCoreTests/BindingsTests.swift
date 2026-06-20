import Testing

@testable import ADHTMLCore

struct BindingsTests {
    @Test
    func `typed DOM events render data-adh-on with the event name`() {
        let arena = CellArena()
        let count = arena.signal(0)
        #expect(
            button { "+" }.on(.click, Behavior.increment(count)).render()
                == #"<button data-adh-on:click="increment#0#1">+</button>"#
        )
        #expect(
            input().on(.focusIn, Behavior.set(count, to: 1)).render()
                == #"<input data-adh-on:focusin="set#0#1">"#
        )
        #expect(
            div { "x" }.on(.custom("dragend"), Behavior.toggle(arena.signal(false))).render()
                == #"<div data-adh-on:dragend="toggle#1">x</div>"#
        )
    }

    @Test
    func `bind accepts a Signal or Computed directly (no .id)`() {
        let arena = CellArena()
        let count = arena.signal(7)
        #expect(
            span { "7" }.bind(.text, to: count).render()
                == #"<span data-adh-bind:text="0">7</span>"#
        )
        let doubled = arena.computed(count.reactive * 2)
        #expect(
            span { "14" }.bind(.text, to: doubled).render()
                == #"<span data-adh-bind:text="1">14</span>"#
        )
    }

    @Test
    func `DOMEvent delegated set mirrors the runtime and custom passes through`() {
        #expect(
            DOMEvent.delegated == [
                "click", "dblclick", "input", "change", "keydown", "keyup", "keypress", "focusin",
                "focusout", "pointerdown", "pointerup", "mousedown", "mouseup", "mouseover", "mouseout",
                "contextmenu"
            ]
        )
        #expect(DOMEvent.custom("dragend").name == "dragend")
        #expect(DOMEvent.click.name == "click")
        #expect(DOMEvent.focusOut.name == "focusout")
    }
}
