import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusBadge v4")
struct NexusBadgeTests {
    @Test("Tone enum exposes the v4 cases")
    func toneCases() {
        #expect(NexusBadgeTone.allCases == [.acc, .pos, .neg, .warn, .info, .muted])
    }

    @Test("Size enum exposes compact and control cases")
    func sizeCases() {
        #expect(NexusBadgeSize.allCases == [.compact, .control])
    }

    @MainActor
    @Test("Defaults to muted tone")
    func defaultTone() {
        let badge = NexusBadge("Today")

        #expect(badge.label == "Today")
        #expect(badge.tone == .muted)
        #expect(badge.size == .compact)
        #expect(badge.textColor.resolvedRGBA == NexusColor.Text.tertiary.resolvedRGBA)
        #expect(badge.borderColor.resolvedRGBA == NexusColor.Line.hairline.resolvedRGBA)
    }

    @MainActor
    @Test("All tones build and map to expected text colours")
    func tonesBuild() {
        // Linear badges are flat neutral status labels — every tone renders the
        // same Storm Cloud (Text.tertiary) ink. Lime is reserved for primary
        // actions / active selection and never appears on badge chrome.
        let expected: [(NexusBadgeTone, Color)] = [
            (.acc, NexusColor.Text.tertiary),
            (.pos, NexusColor.Text.tertiary),
            (.neg, NexusColor.Text.tertiary),
            (.warn, NexusColor.Text.tertiary),
            (.info, NexusColor.Text.tertiary),
            (.muted, NexusColor.Text.tertiary),
        ]

        for (tone, color) in expected {
            let badge = NexusBadge("badge", tone: tone)

            _ = badge.body
            #expect(badge.textColor.resolvedRGBA == color.resolvedRGBA)
        }
    }

    @MainActor
    @Test("Action badges default to control size and retain closure")
    func actionDefaultsToControl() {
        var invoked = false
        let badge = NexusBadge("Open", systemImage: "arrow.right", tone: .acc) {
            invoked = true
        }

        badge.action?()

        #expect(badge.systemImage == "arrow.right")
        #expect(badge.size == .control)
        #expect(badge.minHeight == 32)
        #expect(badge.horizontalPadding == 16)
        #expect(invoked)
        _ = badge.body
    }

    @MainActor
    @Test("Action badges promote explicit compact to control")
    func actionPromotesExplicitCompactToControl() {
        let badge = NexusBadge("Open", tone: .acc, size: .compact) {}

        #expect(badge.size == .control)
        #expect(badge.minHeight == 32)
        #expect(badge.horizontalPadding == 16)
    }

    @MainActor
    @Test("Static badge has no action")
    func staticBadge() {
        let badge = NexusBadge("Tag")

        #expect(badge.action == nil)
    }

    @MainActor
    @Test("Control metrics preserve CTA affordance")
    func controlMetrics() {
        let badge = NexusBadge("Save", tone: .acc, size: .control)

        #expect(badge.size == .control)
        #expect(badge.minHeight == 32)
        #expect(badge.horizontalPadding == 16)
        #expect(badge.verticalPadding == 7)
    }

    @MainActor
    @Test("Compact metrics match Linear badge padding (0 6px)")
    func compactMetrics() {
        let badge = NexusBadge("Today", tone: .muted, size: .compact)

        #expect(badge.size == .compact)
        #expect(badge.minHeight == 18)
        #expect(badge.horizontalPadding == 6)
        #expect(badge.verticalPadding == 0)
    }
}
