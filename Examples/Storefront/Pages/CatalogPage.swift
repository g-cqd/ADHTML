import ADHTML

// A page = data + components. It composes the layout (via the slot) with a product grid. Static itself;
// the interactivity lives only in the `AddToCart` islands nested inside each card.
@Component
struct CatalogPage {
    let products: [Product]

    var body: some HTML {
        PageLayout(pageTitle: "Shop — Acme Tools") {
            h1 { "Shop" }
            div {
                for product in products {
                    ProductCard(product: product)
                }
            }
            .class("grid")
        }
    }
}
