import Foundation
import Testing

@testable import NexusCore

@Suite("BlockMarkdownSerializer (Blocks -> Markdown goldens)")
struct BlockMarkdownSerializerTests {
    @Test("heading levels")
    func headings() {
        #expect(
            BlockMarkdownSerializer.markdown(for: [Block(kind: .heading(level: 2, runs: [InlineRun(text: "Hi")]))])
                == "## Hi"
        )
    }

    @Test("todo, bulleted, numbered, quote prefixes")
    func listLikeBlocks() {
        let runs = [InlineRun(text: "item")]
        #expect(
            BlockMarkdownSerializer.markdown(for: [Block(kind: .todo(taskRef: UUID(), runs: runs))])
                == "- [ ] item"
        )
        #expect(BlockMarkdownSerializer.markdown(for: [Block(kind: .bulleted(runs: runs))]) == "- item")
        #expect(BlockMarkdownSerializer.markdown(for: [Block(kind: .numbered(runs: runs))]) == "1. item")
        #expect(BlockMarkdownSerializer.markdown(for: [Block(kind: .quote(runs: runs))]) == "> item")
    }

    @Test("fenced code with and without language")
    func code() {
        #expect(
            BlockMarkdownSerializer.markdown(for: [Block(kind: .code(language: "swift", text: "let x = 1"))])
                == "```swift\nlet x = 1\n```"
        )
        #expect(
            BlockMarkdownSerializer.markdown(for: [Block(kind: .code(language: nil, text: "plain"))])
                == "```\nplain\n```"
        )
    }

    @Test("divider and embed")
    func dividerAndEmbed() {
        let ref = UUID()
        #expect(BlockMarkdownSerializer.markdown(for: [Block(kind: .divider)]) == "---")
        #expect(
            BlockMarkdownSerializer.markdown(for: [Block(kind: .embed(ref: ref, kind: .task))])
                == "![[\(ref.uuidString)]]"
        )
    }

    @Test("inline marks: bold, italic, code, strike, link, wikilink")
    func inlineMarks() {
        func md(_ run: InlineRun) -> String {
            BlockMarkdownSerializer.markdown(for: [Block(kind: .paragraph(runs: [run]))])
        }
        #expect(md(InlineRun(text: "x", marks: [.bold])) == "**x**")
        #expect(md(InlineRun(text: "x", marks: [.italic])) == "*x*")
        #expect(md(InlineRun(text: "x", marks: [.code])) == "`x`")
        #expect(md(InlineRun(text: "x", marks: [.strike])) == "~~x~~")
        #expect(md(InlineRun(text: "x", marks: [.link(ref: nil, href: "https://x.test")])) == "[x](https://x.test)")
        #expect(md(InlineRun(text: "Topic", marks: [.link(ref: UUID(), href: nil)])) == "[[Topic]]")
    }

    @Test("table emits header separator row")
    func table() {
        let rows = [
            TableRow(cells: [[InlineRun(text: "A")], [InlineRun(text: "B")]]),
            TableRow(cells: [[InlineRun(text: "1")], [InlineRun(text: "2")]]),
        ]
        #expect(
            BlockMarkdownSerializer.markdown(for: [Block(kind: .table(rows: rows))])
                == "| A | B |\n| --- | --- |\n| 1 | 2 |"
        )
    }

    @Test("multiple blocks join with a blank line")
    func blockSeparation() {
        let blocks = [
            Block(kind: .heading(level: 1, runs: [InlineRun(text: "T")])),
            Block(kind: .paragraph(runs: [InlineRun(text: "B")])),
        ]
        #expect(BlockMarkdownSerializer.markdown(for: blocks) == "# T\n\nB")
    }
}
