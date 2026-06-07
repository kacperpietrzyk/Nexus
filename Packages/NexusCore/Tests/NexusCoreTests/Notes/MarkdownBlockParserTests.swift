import Foundation
import Testing

@testable import NexusCore

@Suite("MarkdownBlockParser (Markdown -> Blocks goldens)")
struct MarkdownBlockParserTests {
    // Block-kind comparison helper: ids are freshly minted, so compare on `kind`.
    private func kinds(_ markdown: String) -> [BlockKind] {
        MarkdownBlockParser.parse(markdown).map(\.kind)
    }

    @Test("heading levels parse, beyond 6 falls back to paragraph")
    func headings() {
        #expect(kinds("# A") == [.heading(level: 1, runs: [InlineRun(text: "A")])])
        #expect(kinds("###### F") == [.heading(level: 6, runs: [InlineRun(text: "F")])])
        // 7 hashes is not a heading.
        if case .paragraph = kinds("####### G").first {
        } else {
            Issue.record("7 hashes should be a paragraph")
        }
    }

    @Test("todo parses checked and unchecked, taskRef is a fresh placeholder")
    func todo() {
        let blocks = MarkdownBlockParser.parse("- [ ] do it")
        guard case .todo(let ref, let runs) = blocks.first?.kind else {
            Issue.record("expected todo")
            return
        }
        #expect(ref != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(runs == [InlineRun(text: "do it")])
        // checked variant also parses to a todo
        if case .todo = MarkdownBlockParser.parse("- [x] done").first?.kind {
        } else {
            Issue.record("checked todo should parse")
        }
    }

    @Test("bulleted vs numbered vs quote")
    func listsAndQuote() {
        #expect(kinds("- a") == [.bulleted(runs: [InlineRun(text: "a")])])
        #expect(kinds("1. a") == [.numbered(runs: [InlineRun(text: "a")])])
        #expect(kinds("42. a") == [.numbered(runs: [InlineRun(text: "a")])])
        #expect(kinds("> a") == [.quote(runs: [InlineRun(text: "a")])])
    }

    @Test("fenced code captures language and multiline body")
    func code() {
        let md = "```swift\nlet x = 1\nlet y = 2\n```"
        #expect(kinds(md) == [.code(language: "swift", text: "let x = 1\nlet y = 2")])
        #expect(kinds("```\nplain\n```") == [.code(language: nil, text: "plain")])
    }

    @Test("divider and embed and image")
    func dividerEmbedImage() {
        let ref = UUID()
        #expect(kinds("---") == [.divider])
        #expect(kinds("![[\(ref.uuidString)]]") == [.embed(ref: ref, kind: .note)])
        #expect(kinds("![](photo.png)") == [.image(ref: nil, asset: "photo.png")])
    }

    @Test("table parses header + rows, separator row is consumed")
    func table() {
        let md = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let parsed = kinds(md)
        guard case .table(let rows) = parsed.first, parsed.count == 1 else {
            Issue.record("expected one table block, got \(parsed)")
            return
        }
        #expect(rows.count == 2)
        #expect(rows[0].cells == [[InlineRun(text: "A")], [InlineRun(text: "B")]])
        #expect(rows[1].cells == [[InlineRun(text: "1")], [InlineRun(text: "2")]])
    }

    @Test("inline marks parse")
    func inlineMarks() {
        func runs(_ md: String) -> [InlineRun] {
            MarkdownBlockParser.parseInline(md)
        }
        #expect(runs("**b**") == [InlineRun(text: "b", marks: [.bold])])
        #expect(runs("*i*") == [InlineRun(text: "i", marks: [.italic])])
        #expect(runs("`c`") == [InlineRun(text: "c", marks: [.code])])
        #expect(runs("~~s~~") == [InlineRun(text: "s", marks: [.strike])])
        #expect(runs("[t](https://x.test)") == [InlineRun(text: "t", marks: [.link(ref: nil, href: "https://x.test")])])
        #expect(runs("[[Topic]]") == [InlineRun(text: "Topic", marks: [.link(ref: nil, href: nil)])])
    }

    @Test("nested bold+italic yields a combined mark set")
    func nestedEmphasis() {
        let runs = MarkdownBlockParser.parseInline("***x***")
        #expect(runs.count == 1)
        #expect(runs[0].text == "x")
        #expect(runs[0].marks.contains(.bold))
        #expect(runs[0].marks.contains(.italic))
    }

    @Test("mixed inline text keeps plain segments")
    func mixedInline() {
        let runs = MarkdownBlockParser.parseInline("a **b** c")
        #expect(
            runs == [
                InlineRun(text: "a "),
                InlineRun(text: "b", marks: [.bold]),
                InlineRun(text: " c"),
            ])
    }

    @Test("blank lines separate blocks and are dropped")
    func blankLines() {
        #expect(
            kinds("# T\n\nbody")
                == [
                    .heading(level: 1, runs: [InlineRun(text: "T")]),
                    .paragraph(runs: [InlineRun(text: "body")]),
                ]
        )
    }
}
