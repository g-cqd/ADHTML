import ADHTML
import Testing

struct PageTests {
    @Test
    func `Page assembles a full document from head and content slots (no body collision)`() {
        let html = Page(head: {
            title { "Hi" }
            meta().attribute("charset", "utf-8")
        }) {
            h1 { "Welcome" }
            p { "Body" }
        }
        .render()
        #expect(
            html == #"<!doctype html><html lang="en"><head><title>Hi</title><meta charset="utf-8"></head>"#
                + #"<body><h1>Welcome</h1><p>Body</p></body></html>"#)
    }
}
