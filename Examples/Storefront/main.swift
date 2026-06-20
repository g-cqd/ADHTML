import ADHTML

// A multi-file ADHTML app, one SPM target. Files see each other with no imports; each just `import ADHTML`.
// `swift run Storefront` prints the catalog page: a static perimeter (layout, cards) plus a resumable
// `AddToCart` island per in-stock product, with the inline hydration state appended automatically.
//
// Serving it (with the ADHTMLNIO bridge, ADHTML_NIO): a handler returns the bytes through ADServe's typed
// response — `.adhtml(CatalogPage(products:))` (buffered) or `.adhtmlStream(CatalogPage(products:))`
// (streamed) — and `Static("/assets", root:)` serves the SRI-pinned runtime. No view code changes.

// `Page` (inside the layout) already emits `<!doctype html>`, so render the page directly.
let bytes = try CatalogPage(products: ProductRepository.all()).renderHydratable(arena: CellArena())
print(String(decoding: bytes, as: UTF8.self))
