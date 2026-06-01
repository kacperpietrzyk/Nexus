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
        // Linear redesign restored the restrained semantic map (the LabKit
        // achromatic burn-down is consciously superseded): `.accent` keeps the
        // single lime rim; `.neutral` recedes to Storm Cloud; the temporal /
        // status tones carry tinted ink. `.warning` shares the danger family
        // because amber is forbidden (lime-adjacent).
        let expected: [(NexusChipTone, Color)] = [
            (.neutral, NexusColor.Text.tertiary),
            (.accent, NexusColor.Text.primary),
            (.rose, NexusColor.Status.danger),
            (.positive, NexusColor.Status.success),
            (.negative, NexusColor.Status.danger),
            (.warning, NexusColor.Status.danger),
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
        // Asserted byte-identical to lock the lime-economy invariant.
        #expect(accent.textColor.resolvedRGBA == NexusColor.Text.primary.resolvedRGBA)
        #expect(accent.backgroundColor.resolvedRGBA == NexusColor.Background.controlHover.resolvedRGBA)
        #expect(accent.borderColor.resolvedRGBA == NexusColor.Accent.lime.opacity(0.45).resolvedRGBA)

        // Neutral metadata chip: Storm Cloud ink (demoted from secondary so
        // chrome recedes), flat control fill, neutral rim, no lime.
        #expect(neutral.textColor.resolvedRGBA == NexusColor.Text.tertiary.resolvedRGBA)
        #expect(neutral.backgroundColor.resolvedRGBA == NexusColor.Background.control.resolvedRGBA)
        #expect(neutral.borderColor.resolvedRGBA == NexusColor.Line.hairline.resolvedRGBA)
    }

    @MainActor
    @Test("Restrained semantic recipe: rose/positive use tinted ink + faint wash + subtle rim")
    func restrainedSemanticRecipe() {
        let rose = NexusChip("late", tone: .rose)
        #expect(rose.textColor.resolvedRGBA == NexusColor.Status.danger.resolvedRGBA)
        #expect(rose.backgroundColor.resolvedRGBA == NexusColor.Status.danger.opacity(0.10).resolvedRGBA)
        #expect(rose.borderColor.resolvedRGBA == NexusColor.Status.danger.opacity(0.30).resolvedRGBA)

        let positive = NexusChip("done", tone: .positive)
        #expect(positive.textColor.resolvedRGBA == NexusColor.Status.success.resolvedRGBA)
        #expect(positive.backgroundColor.resolvedRGBA == NexusColor.Status.success.opacity(0.10).resolvedRGBA)
        #expect(positive.borderColor.resolvedRGBA == NexusColor.Status.success.opacity(0.30).resolvedRGBA)
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
