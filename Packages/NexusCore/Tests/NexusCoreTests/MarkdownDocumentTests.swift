import Foundation
import Testing

@testable import NexusCore

@Test func markdownDocument_render_emitsFrontmatterAndBody() {
    let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let updatedAt = Date(timeIntervalSince1970: 1_700_000_500)
    let doc = MarkdownDocument(
        id: id,
        kind: .debug,
        title: "Hello",
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: nil,
        outgoingLinks: [
            MarkdownDocument.LinkRef(
                toKind: .debug,
                toID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                linkKind: .mentions
            )
        ],
        body: "Body text"
    )
    let rendered = doc.render()
    #expect(rendered.contains("id: 11111111-1111-1111-1111-111111111111"))
    #expect(rendered.contains("kind: debug"))
    #expect(rendered.contains("title: Hello"))
    #expect(rendered.contains("# Hello"))
    #expect(rendered.contains("Body text"))
    #expect(rendered.hasSuffix("Body text\n"))
}

@Test func markdownDocument_render_linksSortedDeterministically() {
    let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let aID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    let bID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    // Insert in reverse alphabetic order — exporter must sort them on render.
    let doc = MarkdownDocument(
        id: id, kind: .debug, title: "x",
        createdAt: now, updatedAt: now, deletedAt: nil,
        outgoingLinks: [
            MarkdownDocument.LinkRef(toKind: .debug, toID: bID, linkKind: .mentions),
            MarkdownDocument.LinkRef(toKind: .debug, toID: aID, linkKind: .mentions),
        ],
        body: ""
    )
    let rendered = doc.render()
    let aIndex = rendered.range(of: aID.uuidString)!.lowerBound
    let bIndex = rendered.range(of: bID.uuidString)!.lowerBound
    #expect(aIndex < bIndex)
}

@Test func markdownDocument_filename_isIDDotMd() {
    let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let doc = MarkdownDocument(
        id: id, kind: .debug, title: "x",
        createdAt: .now, updatedAt: .now, deletedAt: nil,
        outgoingLinks: [], body: ""
    )
    #expect(doc.filename == "11111111-1111-1111-1111-111111111111.md")
}
