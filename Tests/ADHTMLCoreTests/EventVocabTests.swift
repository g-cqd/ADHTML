import Testing

@testable import ADHTMLCore

// RFC-0021 P1 (two-way binding) + P4 (extended event + behavior vocabulary), ADR-0018. Byte-exact lowering
// of `i`, the key-filter / prevent / stop refinements, and the new closed behaviors.
struct EventVocabTests {
    // MARK: P1 — `.model(_:)`

    @Test
    func `model emits i and the initial value (no FOUC)`() {
        let arena = CellArena()
        let query = arena.signal("hi")  // id 0
        #expect(input().model(query).render() == #"<input data-i="0" value="hi">"#)
        #expect(input().model(CellID(2)).render() == #"<input data-i="2">"#)
    }

    // MARK: P4 — event refinements

    @Test
    func `keys, prevent and stop lower to their data-adh attributes`() {
        let arena = CellArena()
        let query = arena.signal("")  // id 0
        #expect(
            input().on(.keydown, Behavior.setFromValue(query)).keys("Enter", "Escape")
                .preventDefault().render()
                == #"<input data-c:keydown="d#0" data-j="Enter,Escape" "#
                + #"data-k="">"#)
        #expect(div { "x" }.stopPropagation().render() == #"<div data-l="">x</div>"#)
    }

    // MARK: P4 — the new behaviors' wire tokens

    @Test
    func `the extended behaviors encode the expected attribute tokens`() {
        let arena = CellArena()
        let query = arena.signal("")  // id 0
        let index = arena.signal(0)  // id 1
        let count = arena.signal(5)  // id 2
        let tokens = arena.signal([String]())  // id 3

        #expect(Behavior.setFromValue(query).attributeValue == "d#0")
        #expect(Behavior.listMove(index, by: 1, within: count).attributeValue == "e#1#1#2#false")
        #expect(Behavior.listMove(index, by: -1, within: count, wrap: true).attributeValue == "e#1#-1#2#true")
        #expect(Behavior.commit(tokens, from: query).attributeValue == "f#3#0")
        #expect(Behavior.removeLast(tokens).attributeValue == "g#3")
        #expect(Behavior.commitValue(tokens, clearing: query).attributeValue == "h#3#0")
    }

    @Test
    func `keymap maps several keys to behaviors on one element (P9)`() {
        let arena = CellArena()
        let tokens = arena.signal([String]())  // id 0
        let query = arena.signal("")  // id 1
        #expect(
            input().model(query)
                .keymap([
                    ("Enter", Behavior.commit(tokens, from: query)),
                    ("Backspace", Behavior.removeLast(tokens))
                ])
                .render()
                == #"<input data-i="1" value="" data-y="Enter:f#0#1;Backspace:g#0">"#)
    }

    @Test
    func `the behavior-token set is closed and matches the runtime (Swift<->JS parity)`() {
        // 1-char tokens generated from wire-tokens.json (increment=a … commitValue=h).
        #expect(Behavior.names == ["a", "b", "c", "d", "e", "f", "g", "h"])
    }
}
