import Foundation
import Testing

@testable import NexusCore

/// Block-fixpoint contract for adversarial content (spec §17 strengthened):
/// `parse(serialize(blocks))` must preserve each block's KIND and inline text,
/// not merely the markdown string. The serializer escapes content that would
/// otherwise be misclassified on re-parse; the parser unescapes it.
///
/// Compared on `kind` only (block ids are freshly minted) and with single-run
/// blocks (the parser coalesces adjacent same-mark runs).
@Suite("Markdown escaping (block-fixpoint over adversarial content)")
struct MarkdownEscapingRoundTripTests {
    private func kindFixpoint(
        _ blocks: [Block],
        options: BlockMarkdownSerializer.Options = .plain
    ) -> [BlockKind] {
        let md = BlockMarkdownSerializer.markdown(for: blocks, options: options)
        return MarkdownBlockParser.parse(md).map(\.kind)
    }

    private func paragraph(_ text: String) -> Block {
        Block(kind: .paragraph(runs: [InlineRun(text: text)]))
    }

    // MARK: - N1: paragraph text that looks like a block prefix

    @Test(
        "paragraph text that mimics a block marker round-trips as a paragraph",
        arguments: [
            "- not a bullet",
            "1. not a numbered item",
            "42. not numbered either",
            "# not a heading",
            "###### not a heading",
            "> not a quote",
            "---",
            "![not an embed]",
            "![caption](not-an-image.png)",
            "![[not an embed]]",
        ]
    )
    func blockPrefixParagraphRoundTrips(_ text: String) {
        #expect(kindFixpoint([paragraph(text)]) == [.paragraph(runs: [InlineRun(text: text)])])
    }

    // MARK: - N2: inline metacharacters in plain text

    @Test(
        "literal inline metacharacters in plain text survive the round-trip",
        arguments: [
            "use 2 * 3 and 4 * 5",
            "*not italic*",
            "**not bold**",
            "~~not strike~~",
            "see [brackets] here",
            "a backtick ` mid-line",
            "a path C:\\Users\\me",
            "[[not a wikilink]] really",
        ]
    )
    func inlineMetacharsParagraphRoundTrips(_ text: String) {
        #expect(kindFixpoint([paragraph(text)]) == [.paragraph(runs: [InlineRun(text: text)])])
    }

    // MARK: - Emphasis with an internal literal metachar (advisor regression guard)

    @Test("bold run containing a literal asterisk round-trips")
    func boldWithInternalAsterisk() {
        let blocks = [Block(kind: .paragraph(runs: [InlineRun(text: "a*b", marks: [.bold])]))]
        #expect(kindFixpoint(blocks) == [.paragraph(runs: [InlineRun(text: "a*b", marks: [.bold])])])
    }

    @Test("italic run containing a literal asterisk round-trips")
    func italicWithInternalAsterisk() {
        let blocks = [Block(kind: .paragraph(runs: [InlineRun(text: "a*b", marks: [.italic])]))]
        #expect(kindFixpoint(blocks) == [.paragraph(runs: [InlineRun(text: "a*b", marks: [.italic])])])
    }

    // MARK: - Literal-content scans must stay byte-literal (advisor regression guard)

    @Test("inline code whose content ends in a backslash stays code, not plain text")
    func inlineCodeTrailingBackslash() {
        // `C:\` — the closing backtick must not be skipped as if `\` escaped it.
        let blocks = [Block(kind: .paragraph(runs: [InlineRun(text: "C:\\", marks: [.code])]))]
        #expect(kindFixpoint(blocks) == [.paragraph(runs: [InlineRun(text: "C:\\", marks: [.code])])])
    }

    @Test("a real link still round-trips after escaping is introduced")
    func realLinkStillRoundTrips() {
        let blocks = [
            Block(kind: .paragraph(runs: [InlineRun(text: "site", marks: [.link(ref: nil, href: "https://x.test/p")])]))
        ]
        #expect(
            kindFixpoint(blocks)
                == [.paragraph(runs: [InlineRun(text: "site", marks: [.link(ref: nil, href: "https://x.test/p")])])]
        )
    }

    // MARK: - N4: empty list items keep their kind

    @Test("an empty bullet round-trips as an empty bullet")
    func emptyBullet() {
        #expect(
            kindFixpoint([Block(kind: .bulleted(runs: [InlineRun(text: "")]))])
                == [.bulleted(runs: [InlineRun(text: "")])])
    }

    @Test("an empty numbered item round-trips as an empty numbered item")
    func emptyNumbered() {
        #expect(
            kindFixpoint([Block(kind: .numbered(runs: [InlineRun(text: "")]))])
                == [.numbered(runs: [InlineRun(text: "")])])
    }

    @Test("an empty quote round-trips as an empty quote")
    func emptyQuote() {
        #expect(
            kindFixpoint([Block(kind: .quote(runs: [InlineRun(text: "")]))])
                == [.quote(runs: [InlineRun(text: "")])])
    }

    // MARK: - Inbound: raw markdown with a backslash before a NON-escape char
    // (paste-as-markdown, MCP write, and the V8→V9 body→Note migration all call
    // `parse` directly on un-escaped user text — the backslash must survive).

    @Test(
        "a backslash before a non-punctuation char is kept literally on inbound parse",
        arguments: [
            "a path C:\\Users\\me",  // C:\Users\me — Windows path
            "regex \\d+ and \\w*",  // \d+ \w* — backslashes before letters
            "trailing slash\\",  // lone trailing backslash
        ]
    )
    func inboundBackslashBeforeNonPunctuationSurvives(_ raw: String) {
        #expect(MarkdownBlockParser.parse(raw).map(\.kind) == [.paragraph(runs: [InlineRun(text: raw)])])
    }

    @Test("a backslash before a punctuation char unescapes on inbound parse")
    func inboundBackslashBeforePunctuationUnescapes() {
        // \*literal\* — escaped stars are literal asterisks, NOT italic.
        #expect(
            MarkdownBlockParser.parse("\\*literal\\*").map(\.kind)
                == [.paragraph(runs: [InlineRun(text: "*literal*")])]
        )
    }

    @Test("an empty todo round-trips as a todo (not a bullet), preserving the empty label")
    func emptyTodo() {
        let md = BlockMarkdownSerializer.markdown(for: [Block(kind: .todo(taskRef: UUID(), runs: [InlineRun(text: "")]))])
        let kind = MarkdownBlockParser.parse(md).first?.kind
        guard case .todo(_, let runs) = kind else {
            Issue.record("expected a todo, got \(String(describing: kind))")
            return
        }
        #expect(runs == [InlineRun(text: "")])
    }
}
