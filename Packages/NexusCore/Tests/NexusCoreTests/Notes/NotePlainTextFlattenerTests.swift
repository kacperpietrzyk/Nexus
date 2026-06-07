import Foundation
import Testing

@testable import NexusCore

struct NotePlainTextFlattenerTests {
    @Test func flattensVisibleTextWithoutSigils() {
        let blocks = [
            Block(kind: .heading(level: 2, runs: [InlineRun(text: "Heading")])),
            Block(kind: .paragraph(runs: [InlineRun(text: "Bold ", marks: [.bold]), InlineRun(text: "tail")])),
            Block(kind: .bulleted(runs: [InlineRun(text: "item")])),
            Block(kind: .code(language: "swift", text: "let x = 1")),
        ]
        let text = NotePlainTextFlattener.plainText(for: blocks)
        #expect(text == "Heading\nBold tail\nitem\nlet x = 1")
    }

    @Test func dropsDividerAndEmbedAndEmptyLines() {
        let blocks = [
            Block(kind: .divider),
            Block(kind: .embed(ref: UUID(), kind: .task)),
            Block(kind: .paragraph(runs: [InlineRun(text: "")])),
            Block(kind: .paragraph(runs: [InlineRun(text: "kept")])),
        ]
        #expect(NotePlainTextFlattener.plainText(for: blocks) == "kept")
    }

    @Test func flattensTableCellsSpaceAndRowNewlineJoined() {
        let blocks = [
            Block(
                kind: .table(rows: [
                    TableRow(cells: [[InlineRun(text: "a")], [InlineRun(text: "b")]]),
                    TableRow(cells: [[InlineRun(text: "c")], [InlineRun(text: "d")]]),
                ]))
        ]
        #expect(NotePlainTextFlattener.plainText(for: blocks) == "a b\nc d")
    }
}
