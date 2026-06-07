import Foundation
import Testing

@testable import NexusCore

@Suite("Block / InlineRun / Mark Codable")
struct BlockTests {
    private func roundTrip(_ block: Block) throws -> Block {
        let data = try JSONEncoder().encode(block)
        return try JSONDecoder().decode(Block.self, from: data)
    }

    @Test("block id is stable across decode/encode")
    func idIsStable() throws {
        let id = UUID()
        let block = Block(id: id, kind: .paragraph(runs: [InlineRun(text: "hello")]))
        let decoded = try roundTrip(block)
        #expect(decoded.id == id)
    }

    @Test("paragraph round-trips with inline runs and marks")
    func paragraphRoundTrip() throws {
        let runs = [
            InlineRun(text: "bold", marks: [.bold]),
            InlineRun(text: " and ", marks: []),
            InlineRun(text: "code", marks: [.code, .italic]),
        ]
        let block = Block(kind: .paragraph(runs: runs))
        #expect(try roundTrip(block) == block)
    }

    @Test("all block variants round-trip identically")
    func allVariantsRoundTrip() throws {
        let ref = UUID()
        let runs = [InlineRun(text: "x", marks: [.strike])]
        let variants: [BlockKind] = [
            .paragraph(runs: runs),
            .heading(level: 2, runs: runs),
            .todo(taskRef: ref, runs: runs),
            .bulleted(runs: runs),
            .numbered(runs: runs),
            .quote(runs: runs),
            .code(language: "swift", text: "let x = 1"),
            .code(language: nil, text: "plain"),
            .divider,
            .image(ref: ref, asset: "path/to.png"),
            .image(ref: nil, asset: nil),
            .embed(ref: ref, kind: .task),
            .table(rows: [TableRow(cells: [[InlineRun(text: "a")], [InlineRun(text: "b")]])]),
            .html(raw: "<p>raw</p>"),
        ]
        for kind in variants {
            let block = Block(kind: kind)
            #expect(try roundTrip(block) == block)
        }
    }

    @Test("link mark round-trips with ref and href, including nils")
    func linkMarkRoundTrip() throws {
        let ref = UUID()
        let cases: [Mark] = [
            .link(ref: ref, href: "https://example.com"),
            .link(ref: ref, href: nil),
            .link(ref: nil, href: "https://example.com"),
            .link(ref: nil, href: nil),
        ]
        for mark in cases {
            let block = Block(kind: .paragraph(runs: [InlineRun(text: "t", marks: [mark])]))
            #expect(try roundTrip(block) == block)
        }
    }

    @Test("encoded shape uses stable type discriminators")
    func encodedShapeHasStableDiscriminators() throws {
        let block = Block(kind: .todo(taskRef: UUID(), runs: [InlineRun(text: "do it")]))
        let data = try JSONEncoder().encode(block)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"type\":\"todo\""))
        #expect(json.contains("\"taskRef\""))
    }

    /// The `type` discriminator strings land in CloudKit inside `Note.contentData`.
    /// Pin every one of them — renaming a case would silently break decode of
    /// every previously-persisted note. Round-trip tests do NOT catch this
    /// (encode + decode share the same discriminator).
    @Test("every BlockKind discriminator string is frozen")
    func blockKindDiscriminatorsAreFrozen() throws {
        let ref = UUID()
        let runs = [InlineRun(text: "x")]
        let expected: [(BlockKind, String)] = [
            (.paragraph(runs: runs), "paragraph"),
            (.heading(level: 1, runs: runs), "heading"),
            (.todo(taskRef: ref, runs: runs), "todo"),
            (.bulleted(runs: runs), "bulleted"),
            (.numbered(runs: runs), "numbered"),
            (.quote(runs: runs), "quote"),
            (.code(language: nil, text: "c"), "code"),
            (.divider, "divider"),
            (.image(ref: nil, asset: nil), "image"),
            (.embed(ref: ref, kind: .task), "embed"),
            (.table(rows: []), "table"),
            (.html(raw: "<p/>"), "html"),
        ]
        for (kind, tag) in expected {
            let json = try #require(String(data: JSONEncoder().encode(Block(kind: kind)), encoding: .utf8))
            #expect(json.contains("\"type\":\"\(tag)\""), "BlockKind \(tag) discriminator drifted")
        }
    }

    @Test("every Mark discriminator string is frozen")
    func markDiscriminatorsAreFrozen() throws {
        let expected: [(Mark, String)] = [
            (.bold, "bold"),
            (.italic, "italic"),
            (.code, "code"),
            (.strike, "strike"),
            (.link(ref: nil, href: nil), "link"),
        ]
        for (mark, tag) in expected {
            let json = try #require(String(data: JSONEncoder().encode(mark), encoding: .utf8))
            #expect(json.contains("\"type\":\"\(tag)\""), "Mark \(tag) discriminator drifted")
        }
    }

    @Test("array of blocks round-trips preserving order and ids")
    func blockArrayRoundTrip() throws {
        let blocks = [
            Block(kind: .heading(level: 1, runs: [InlineRun(text: "Title")])),
            Block(kind: .paragraph(runs: [InlineRun(text: "Body")])),
            Block(kind: .divider),
        ]
        let data = try JSONEncoder().encode(blocks)
        let decoded = try JSONDecoder().decode([Block].self, from: data)
        #expect(decoded == blocks)
        #expect(decoded.map(\.id) == blocks.map(\.id))
    }
}
