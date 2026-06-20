import ADHTML

// An INTERACTIVE component: it has @State, so it AUTO-WRAPS as a resumable hydration island — note there
// is no `Island`, no `scope:`, and no `.id` anywhere in this file. The client runtime wires the stepper;
// the `+`/`−` buttons drive the `quantity` signal and the bound `<span>` updates. Typed events
// (`.on(.click, …)`) and a direct `Signal` binding (no `.id` ceremony) round it out.
@Component
struct AddToCart {
    let productID: String
    @State var quantity = 0

    var body: some HTML {
        div {
            button { "−" }.on(.click, Behavior.increment(quantitySignal, by: -1))
            span { String(quantity) }.bind(.text, to: quantitySignal)
            button { "+" }.on(.click, Behavior.increment(quantitySignal))
        }
        .class("add-to-cart")
        .data("product", productID)
    }
}
