import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusChip v4")
struct NexusChipTests {
    @Test("Tone enum exposes the v4 cases")
    func toneCases() {
        #expect(NexusChipTone.allCases == [.neutral, .accent, .rose, .positive, .negative, .warning])
    }

    @MainActor
    @Test("Defaults to neutral tone")
    func defaultTone() {
        let chip = NexusChip("backend")

        #expect(chip.label == "backend")
        #expect(chip.tone == .neutral)
        #expect(chip.textColor.resolvedRGBA == NexusColor.Text.tertiary.resolvedRGBA)
        #expect(chip.borderColor.resolvedRGBA == NexusColor.Line.hairline.resolvedRGBA)
    }

    @MainActor
    @Test("All tones build and map to expected text colours")
    func tonesBuild() {
        let expected: [(NexusChipTone, Color)] = [
            (.neutral, NexusColor.Text.tertiary),
            (.accent, NexusColor.Text.primary),
            (.rose, NexusColor.Text.primary),
            (.positive, NexusColor.Text.secondary),
            (.negative, NexusColor.Text.primary),
            (.warning, NexusColor.Text.secondary),
        ]

        for (tone, color) in expected {
            let chip = NexusChip("chip", tone: tone)

            _ = chip.body
            #expect(chip.textColor.resolvedRGBA == color.resolvedRGBA)
        }
    }

    @MainActor
    @Test("Accent audit: accent = strong ink ladder, neutral = faint, both achromatic")
    func achromaticAccentAudit() {
        let accent = NexusChip("x", tone: .accent)
        let neutral = NexusChip("y", tone: .neutral)

        #expect(accent.textColor.resolvedRGBA == NexusColor.Text.primary.resolvedRGBA)
        #expect(accent.backgroundColor.resolvedRGBA == Color.white.opacity(0.10).resolvedRGBA)
        #expect(neutral.textColor.resolvedRGBA == NexusColor.Text.tertiary.resolvedRGBA)
        #expect(neutral.backgroundColor.resolvedRGBA == Color.white.opacity(0.055).resolvedRGBA)
    }

    @MainActor
    @Test("System image is retained")
    func systemImage() {
        let chip = NexusChip("late", systemImage: "exclamationmark.triangle.fill", tone: .rose)

        #expect(chip.systemImage == "exclamationmark.triangle.fill")
        _ = chip.body
    }

    @MainActor
    @Test("Remove action is retained and invokable")
    func onRemove() {
        var invoked = false
        let chip = NexusChip("test", onRemove: { invoked = true })

        chip.onRemove?()

        #expect(invoked)
    }
}
