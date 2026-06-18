import Testing

@testable import NexusUI

@Suite struct MarkdownExportTests {
    @Test func entityFormatsTitleBodyAndMetadata() {
        let md = MarkdownExport.entity(
            title: "Ship release",
            body: "Cut the build, then tag it.",
            metadata: ["Due: tomorrow", "Priority: high"]
        )
        #expect(
            md == """
                # Ship release

                - Due: tomorrow
                - Priority: high

                Cut the build, then tag it.
                """
        )
    }

    @Test func entityOmitsEmptySections() {
        #expect(MarkdownExport.entity(title: "Just a title") == "# Just a title")
        #expect(MarkdownExport.entity(title: "", body: "body only") == "body only")
    }

    @Test func entityDropsBlankMetadataLines() {
        let md = MarkdownExport.entity(title: "T", metadata: ["keep", "   ", ""])
        #expect(md == "# T\n\n- keep")
    }

    @Test func entityTrimsTitleAndBody() {
        let md = MarkdownExport.entity(title: "  Padded  ", body: "\n\nbody\n\n")
        #expect(md == "# Padded\n\nbody")
    }

    @Test func listJoinsWithHorizontalRule() {
        let md = MarkdownExport.list(["# A", "# B"])
        #expect(md == "# A\n\n---\n\n# B")
    }

    @Test func listSkipsEmptyBlocks() {
        #expect(MarkdownExport.list(["# A", "  ", ""]) == "# A")
    }

    @Test func checklistItemFormatsCheckbox() {
        #expect(MarkdownExport.checklistItem("Write tests", done: true) == "- [x] Write tests")
        #expect(MarkdownExport.checklistItem("  TODO ", done: false) == "- [ ] TODO")
    }
}
