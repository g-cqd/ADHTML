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
        #expect(input().model(query).render() == #"<input i="0" value="hi">"#)
        #expect(input().model(CellID(2)).render() == #"<input i="2">"#)
    }

    // MARK: P4 — event refinements

    @Test
    func `keys, prevent and stop lower to their data-adh attributes`() {
        let arena = CellArena()
        let query = arena.signal("")  // id 0
        #expect(
            input().on(.keydown, Behavior.setFromValue(query)).keys("Enter", "Escape")
                .preventDefault().render()
                == #"<input c:keydown="setFromValue#0" j="Enter,Escape" "#
                + #"k="">"#)
        #expect(div { "x" }.stopPropagation().render() == #"<div l="">x</div>"#)
    }

    // MARK: P4 — the new behaviors' wire tokens

    @Test
    func `the extended behaviors encode the expected attribute tokens`() {
        let arena = CellArena()
        let query = arena.signal("")  // id 0
        let index = arena.signal(0)  // id 1
        let count = arena.signal(5)  // id 2
        let tokens = arena.signal([String]())  // id 3

        #expect(Behavior.setFromValue(query).attributeValue == "setFromValue#0")
        #expect(Behavior.listMove(index, by: 1, within: count).attributeValue == "listMove#1#1#2#false")
        #expect(Behavior.listMove(index, by: -1, within: count, wrap: true).attributeValue == "listMove#1#-1#2#true")
        #expect(Behavior.commit(tokens, from: query).attributeValue == "commit#3#0")
        #expect(Behavior.removeLast(tokens).attributeValue == "removeLast#3")
    }

    @Test
    func `the behavior-name set is closed and matches the runtime (Swift<->JS parity)`() {
        #expect(
            Behavior.names == [
                "increment", "toggle", "set", "setFromValue", "listMove", "commit", "removeLast"
            ])
    }
}
