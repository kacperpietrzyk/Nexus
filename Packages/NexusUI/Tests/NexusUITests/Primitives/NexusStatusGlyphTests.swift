import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusStatusGlyph v4")
struct NexusStatusGlyphTests {
    @MainActor
    @Test("All cases instantiate")
    func cases() {
        let glyphs = [
            NexusStatusGlyph(.todo),
            NexusStatusGlyph(.inProgress(0.4)),
            NexusStatusGlyph(.inReview),
            NexusStatusGlyph(.done),
            NexusStatusGlyph(.cancelled),
        ]

        for glyph in glyphs {
            _ = glyph.body
        }
    }

    @MainActor
    @Test("Morph: the always-mounted checkmark is active only for .done")
    func morphContract() {
        #expect(NexusStatusGlyph(.done).isDone)
        #expect(!NexusStatusGlyph(.todo).isDone)
        #expect(!NexusStatusGlyph(.inProgress(0.5)).isDone)
        #expect(!NexusStatusGlyph(.inReview).isDone)
        #expect(!NexusStatusGlyph(.cancelled).isDone)
    }

    @MainActor
    @Test("inProgress clamps to 0...1")
    func clamp() {
        #expect(NexusStatusGlyph.clampedProgress(-0.5) == 0)
        #expect(NexusStatusGlyph.clampedProgress(0.4) == 0.4)
        #expect(NexusStatusGlyph.clampedProgress(2.0) == 1)
    }

    @MainActor
    @Test("Accessibility labels describe the status state")
    func accessibilityLabels() {
        #expect(NexusStatusGlyph(.todo).accessibilityLabel == "To do")
        #expect(NexusStatusGlyph(.inProgress(0.5)).accessibilityLabel == "In progress")
        #expect(NexusStatusGlyph(.inReview).accessibilityLabel == "In review")
        #expect(NexusStatusGlyph(.done).accessibilityLabel == "Done")
        #expect(NexusStatusGlyph(.cancelled).accessibilityLabel == "Cancelled")
    }

    @MainActor
    @Test("Accessibility value reports progress percent for progress states")
    func accessibilityValues() {
        #expect(NexusStatusGlyph(.todo).accessibilityValue.isEmpty)
        #expect(NexusStatusGlyph(.inProgress(0.0)).accessibilityValue == "0 percent")
        #expect(NexusStatusGlyph(.inProgress(0.5)).accessibilityValue == "50 percent")
        #expect(NexusStatusGlyph(.inProgress(2.0)).accessibilityValue == "100 percent")
        // `.inReview` must NOT fabricate progress — empty, no "percent"
        #expect(NexusStatusGlyph(.inReview).accessibilityValue.isEmpty)
        #expect(!NexusStatusGlyph(.inReview).accessibilityValue.contains("percent"))
        #expect(NexusStatusGlyph(.done).accessibilityValue.isEmpty)
        #expect(NexusStatusGlyph(.cancelled).accessibilityValue.isEmpty)
    }
}
