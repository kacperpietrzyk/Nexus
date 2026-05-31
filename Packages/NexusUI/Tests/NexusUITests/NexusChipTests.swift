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
        #expect(chip.textColor.resolvedRGBA == NexusColor.Text.secondary.resolvedRGBA)
        #expect(chip.borderColor.resolvedRGBA == NexusColor.Line.hairline.resolvedRGBA)
    }

    @MainActor
    @Test("All tones build and map to expected text colours")
    func tonesBuild() {
        // Mirrors current NexusChip source: the single `.accent` (active /
        // selected) chip earns Porcelain ink + a lime rim; every other tone uses
        // Text.secondary. NOTE: the design spec (and the NexusBadge sibling) call
        // for Storm Cloud / Text.tertiary on neutral chips — this asserts the
        // shipped value pending spec reconciliation by the NexusChip owner.
        let expected: [(NexusChipTone, Color)] = [
            (.neutral, NexusColor.Text.secondary),
            (.accent, NexusColor.Text.primary),
            (.rose, NexusColor.Text.secondary),
            (.positive, NexusColor.Text.secondary),
            (.negative, NexusColor.Text.secondary),
            (.warning, NexusColor.Text.secondary),
        ]

        for (tone, color) in expected {
            let chip = NexusChip("chip", tone: tone)

            _ = chip.body
            #expect(chip.textColor.resolvedRGBA == color.resolvedRGBA)
        }
    }

    @MainActor
    @Test("Lime economy: accent chip gets the only lime rim, neutral stays flat")
    func limeEconomyAudit() {
        let accent = NexusChip("x", tone: .accent)
        let neutral = NexusChip("y", tone: .neutral)

        // Accent is the single active/selected chip: Porcelain ink, a flat
        // charcoal lift, and the one place lime is allowed — a subtle rim.
        #expect(accent.textColor.resolvedRGBA == NexusColor.Text.primary.resolvedRGBA)
        #expect(accent.backgroundColor.resolvedRGBA == NexusColor.Background.controlHover.resolvedRGBA)
        #expect(accent.borderColor.resolvedRGBA == NexusColor.Accent.lime.opacity(0.45).resolvedRGBA)

        // Neutral metadata chip: flat control fill, neutral rim, no lime.
        // (Text.secondary mirrors current source; spec calls for Text.tertiary —
        // see note in `tonesBuild`, pending NexusChip owner reconciliation.)
        #expect(neutral.textColor.resolvedRGBA == NexusColor.Text.secondary.resolvedRGBA)
        #expect(neutral.backgroundColor.resolvedRGBA == NexusColor.Background.control.resolvedRGBA)
        #expect(neutral.borderColor.resolvedRGBA == NexusColor.Line.hairline.resolvedRGBA)
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
