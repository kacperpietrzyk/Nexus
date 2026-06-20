import CoreGraphics
import NexusCore
import Testing

@testable import NotesFeature

@Suite("BlockRhythm")
struct BlockRhythmTests {
    @Test("first block has no top gap")
    func first() {
        #expect(BlockRhythm.spacingBefore(.paragraph(runs: []), previous: nil) == 0)
    }

    @Test("heading gets a large gap above when not first")
    func heading() {
        #expect(BlockRhythm.spacingBefore(.heading(level: 2, runs: []), previous: .paragraph(runs: [])) == 24)
    }

    @Test("consecutive same-kind list items pack tight")
    func tightLists() {
        #expect(BlockRhythm.spacingBefore(.bulleted(runs: []), previous: .bulleted(runs: [])) == 2)
        #expect(BlockRhythm.spacingBefore(.numbered(runs: []), previous: .numbered(runs: [])) == 2)
    }

    @Test("paragraph after paragraph gets a small gap; a kind change gets medium")
    func paragraphsAndChanges() {
        #expect(BlockRhythm.spacingBefore(.paragraph(runs: []), previous: .paragraph(runs: [])) == 8)
        #expect(BlockRhythm.spacingBefore(.quote(runs: []), previous: .paragraph(runs: [])) == 12)
    }
}
