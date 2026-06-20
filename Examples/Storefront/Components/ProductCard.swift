import ADHTML

// A static component — no @State, so it renders INLINE (no island, ships zero JS). It composes a nested
// interactive component (`AddToCart`), which becomes its own island automatically. Shows typed enums
// (`loading(.lazy)`) and builder control flow (`if`/`else`).
@Component
struct ProductCard {
    let product: Product

    var body: some HTML {
        article {
            img().src(product.imageURL).alt(product.name).loading(.lazy)
            h3 { product.name }
            p { product.price }.class("price")
            if product.inStock {
                AddToCart(productID: product.id)  // interactive -> its own island
            } else {
                span { "Sold out" }.class("muted")
            }
        }
        .class("card")
    }
}
