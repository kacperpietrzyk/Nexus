import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusDotIndicator v4")
struct NexusDotIndicatorTests {
    @Test("Tone enum exposes coss cases")
    func toneCases() {
        #expect(NexusDotTone.allCases == [.acc, .pos, .neg, .warn, .info, .muted])
    }

    @MainActor
    @Test("Dot size matches canvas")
    func size() {
        #expect(NexusDotIndicator.side == 6)
    }

    @MainActor
    @Test("All tones resolve expected colors")
    func colors() {
        // Lime marks the single active/accent dot; status tones carry semantic
        // meaning (success/danger/info); warn + muted stay neutral.
        let expected: [(NexusDotTone, Color)] = [
            (.acc, NexusColor.Accent.lime),
            (.pos, NexusColor.Status.success),
            (.neg, NexusColor.Status.danger),
            (.warn, NexusColor.Text.secondary),
            (.info, NexusColor.Status.info),
            (.muted, NexusColor.Text.muted),
        ]

        for (tone, color) in expected {
            let dot = NexusDotIndicator(tone)

            #expect(dot.color.resolvedRGBA == color.resolvedRGBA)
            _ = dot.body
        }
    }

    @MainActor
    @Test("Linear dots carry no ring (flat fill, no glow)")
    func ring() {
        for tone in NexusDotTone.allCases {
            let dot = NexusDotIndicator(tone)

            #expect(dot.ringColor == nil)
        }
    }
}
