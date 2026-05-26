import NexusUI
import SwiftUI
import Testing

@testable import TasksFeature

@Suite("DigestRenderer")
struct DigestRendererTests {
    @Test("strips accent and mono markers while preserving text order")
    func stripsMarkers() {
        let digest = DigestRenderer.attributedString(
            for: "Review [[accent]]NEX-204[[/accent]] and update [[mono]]bench.swift[[/mono]]."
        )

        #expect(String(digest.characters) == "Review NEX-204 and update bench.swift.")
    }

    @Test("leaves unmatched marker text untouched")
    func unmatchedMarkersStayVisible() {
        let digest = DigestRenderer.attributedString(for: "Review [[accent]]NEX-204")

        #expect(String(digest.characters) == "Review [[accent]]NEX-204")
    }

    // MP-2 achromatic gate: emphasis span must render with Text.primary (achromatic),
    // not the legacy NexusColor.Accent.solid chromatic value.
    @Test("emphasis span foreground is achromatic Text.primary")
    func emphasisSpanIsAchromatic() {
        let digest = DigestRenderer.attributedString(for: "Do [[accent]]this[[/accent]] now.")
        // Walk attributed string runs to find the "this" segment and check its foreground.
        var found = false
        for run in digest.runs {
            let segment = String(digest[run.range].characters)
            if segment == "this" {
                let color = run.foregroundColor
                // Expect Text.primary — reject nil (unstyled) and any non-primary value.
                #expect(color == NexusColor.Text.primary)
                found = true
            }
        }
        #expect(found, "Expected to find 'this' span in attributed string runs")
    }
}
