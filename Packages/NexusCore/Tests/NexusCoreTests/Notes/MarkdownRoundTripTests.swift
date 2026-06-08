import Foundation
import Testing

@testable import NexusCore

/// Round-trip contract (spec §17): for supported syntax, the Markdown
/// serializer and parser form a **fixpoint** —
/// `serialize(parse(md)) == md`.
///
/// Block-level identity is intentionally NOT asserted: markdown does not carry a
/// todo's `taskRef`, an embed's `ItemKind`, a wikilink's `ref`, or block `id`s.
/// The fixpoint is over the *markdown string*, which sidesteps those gaps.
///
/// A fixpoint alone could pass for a serializer/parser pair that agree on
/// garbage; the golden tests in the sibling suites anchor each direction's
/// correctness. This suite proves self-consistency.
@Suite("Markdown round-trip (serialize ∘ parse fixpoint)")
struct MarkdownRoundTripTests {
    private func fixpoint(_ markdown: String) {
        let once = BlockMarkdownSerializer.markdown(for: MarkdownBlockParser.parse(markdown))
        #expect(once == markdown, "fixpoint drifted")
        // Idempotent: a second pass is stable too.
        let twice = BlockMarkdownSerializer.markdown(for: MarkdownBlockParser.parse(once))
        #expect(twice == once)
    }

    @Test(
        "supported syntax is a markdown fixpoint",
        arguments: [
            "# Heading One",
            "## Heading Two",
            "###### Heading Six",
            "Just a plain paragraph.",
            "- [ ] a task in a note",
            "- a bullet item",
            "1. a numbered item",
            "> a quoted line",
            "---",
            "```swift\nlet x = 1\nlet y = 2\n```",
            "```\nno language here\n```",
            "![](images/photo.png)",
            "Text with **bold** word.",
            "Text with *italic* word.",
            "Text with ***bold italic*** word.",
            "Text with `code` span.",
            "Text with ~~strike~~ word.",
            "Text with [a link](https://example.test/path).",
            "Text with [[Wiki Target]] reference.",
            "| A | B |\n| --- | --- |\n| 1 | 2 |",
            "- first\n- second\n- third",
            "- [ ] one\n- [ ] two",
            // Canonical numbered form: the serializer emits `1.` for every item
            // (the model carries no ordinal), so the fixpoint pins `1.`-per-item,
            // not `1. / 2.`.
            "1. one\n1. two",
        ]
    )
    func singleBlockFixpoint(_ markdown: String) {
        fixpoint(markdown)
    }

    @Test("embed block is a fixpoint (uuid preserved, kind defaulted)")
    func embedFixpoint() {
        let md = "![[\(UUID().uuidString)]]"
        fixpoint(md)
    }

    @Test("multi-block document is a fixpoint")
    func multiBlockFixpoint() {
        let doc = [
            "# Project Notes",
            "",
            "An intro paragraph with **bold** and a [[Linked Note]].",
            "",
            "- [ ] first task",
            "- [ ] second task",
            "",
            "> a quote",
            "",
            "```swift",
            "let answer = 42",
            "```",
            "",
            "---",
        ].joined(separator: "\n")
        fixpoint(doc)
    }

    @Test("note content blob -> markdown -> blob is stable for refs")
    func contentBlobRoundTripThroughMarkdown() throws {
        // Build blocks that DO carry refs, serialize to markdown, reparse. The
        // markdown string round-trips even though refs/ids/kinds are reset — that
        // is the documented boundary (reconciler rebinds refs).
        let blocks = [
            Block(kind: .heading(level: 1, runs: [InlineRun(text: "Title")])),
            Block(kind: .todo(taskRef: UUID(), runs: [InlineRun(text: "do it")])),
            Block(kind: .paragraph(runs: [InlineRun(text: "see", marks: [.link(ref: UUID(), href: nil)])])),
        ]
        let md1 = BlockMarkdownSerializer.markdown(for: blocks)
        let md2 = BlockMarkdownSerializer.markdown(for: MarkdownBlockParser.parse(md1))
        #expect(md1 == md2)
    }

    @Test("task ref marker preserves todo identity when requested")
    func todoTaskRefMarkerRoundTripsWhenRequested() throws {
        let taskID = UUID()
        let blocks = [
            Block(kind: .todo(taskRef: taskID, runs: [InlineRun(text: "do it")]))
        ]

        let markdown = BlockMarkdownSerializer.markdown(for: blocks, options: .mcpRoundTrip)
        #expect(markdown == "- [ ] do it <!-- nexus-task:\(taskID.uuidString) -->")

        let reparsed = MarkdownBlockParser.parse(markdown)
        let reparsedKind = try #require(reparsed.first?.kind)
        guard case .todo(let reparsedTaskID, let runs) = reparsedKind else {
            Issue.record("Expected a todo block")
            return
        }
        #expect(reparsedTaskID == taskID)
        #expect(runs == [InlineRun(text: "do it")])
    }
}
