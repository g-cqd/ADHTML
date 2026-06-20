// Plain value types — the app's data. No ADHTML import needed; models are just Swift.

struct Product: Sendable, Identifiable {
    let id: String
    let name: String
    let price: String  // pre-formatted, e.g. "$19.99" (keeps the example Foundation-free)
    let imageURL: String
    let inStock: Bool
}

/// A stand-in data source (a real app would query a store).
enum ProductRepository {
    static func all() -> [Product] {
        [
            Product(
                id: "wrench", name: "Adjustable Wrench", price: "$19.99", imageURL: "/img/wrench.jpg", inStock: true),
            Product(
                id: "driver", name: "Ratcheting Driver", price: "$24.50", imageURL: "/img/driver.jpg", inStock: true),
            Product(id: "pliers", name: "Locking Pliers", price: "$15.00", imageURL: "/img/pliers.jpg", inStock: false),
            Product(id: "level", name: "Laser Level", price: "$59.00", imageURL: "/img/level.jpg", inStock: true)
        ]
    }
}
