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
        let expected: [(NexusDotTone, Color)] = [
            (.acc, NexusColor.Text.primary),
            (.pos, NexusColor.Text.secondary),
            (.neg, NexusColor.Text.primary),
            (.warn, NexusColor.Text.secondary),
            (.info, NexusColor.Text.tertiary),
            (.muted, NexusColor.Text.muted),
        ]

        for (tone, color) in expected {
            let dot = NexusDotIndicator(tone)

            #expect(dot.color.resolvedRGBA == color.resolvedRGBA)
            _ = dot.body
        }
    }

    @MainActor
    @Test("Only accent tone gets a soft ring")
    func ring() {
        for tone in NexusDotTone.allCases {
            let dot = NexusDotIndicator(tone)

            if tone == .acc {
                #expect(dot.ringColor != nil)
                #expect(dot.ringColor!.resolvedRGBA == NexusColor.Glass.surface3.resolvedRGBA)
            } else {
                #expect(dot.ringColor == nil)
            }
        }
    }
}
