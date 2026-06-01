import SwiftUI
import Testing

@testable import NexusUI

@Test func type_displayMetrics_match() {
    let m = NexusType.Metrics.display
    #expect(m.size == 48)
    #expect(m.lineHeight == 1.06)
    #expect(m.tracking == -0.22 / 48)
    #expect(m.weight == .semibold)
}

@Test func type_h1Metrics_match() {
    let m = NexusType.Metrics.h1
    #expect(m.size == 32)
    #expect(m.tracking == -0.22 / 32)
    #expect(m.weight == .semibold)
}

@Test func type_h2Metrics_match() {
    #expect(NexusType.Metrics.h2.size == 24)
    #expect(NexusType.Metrics.h2.tracking == -0.22 / 24)
    #expect(NexusType.Metrics.h2.weight == .semibold)
}

@Test func type_h3Metrics_match() {
    #expect(NexusType.Metrics.h3.size == 17)
    #expect(NexusType.Metrics.h3.weight == .medium)
    #expect(NexusType.Metrics.h3.tracking == -0.13 / 17)
}

@Test func type_bodyMetrics_match() {
    #expect(NexusType.Metrics.body.size == 14)
    #expect(NexusType.Metrics.body.lineHeight == 1.45)
    #expect(NexusType.Metrics.body.tracking == -0.13 / 14)
}

@Test func type_bodySmallMetrics_match() {
    #expect(NexusType.Metrics.bodySmall.size == 13)
    #expect(NexusType.Metrics.bodySmall.tracking == -0.12 / 13)
}

@Test func type_metaMetrics_match() {
    #expect(NexusType.Metrics.meta.size == 12)
    #expect(NexusType.Metrics.meta.tracking == -0.11 / 12)
}

@Test func type_captionMetrics_match() {
    #expect(NexusType.Metrics.caption.size == 11)
    #expect(NexusType.Metrics.caption.tracking == -0.10 / 11)
}

@Test func type_eyebrowMetrics_match() {
    let m = NexusType.Metrics.eyebrow
    #expect(m.size == 10)
    #expect(m.tracking == 0.18)
    #expect(m.weight == .semibold)
    #expect(m.uppercase == true)
}

@Test func type_lineHeights_matchSpec() {
    #expect(NexusType.Metrics.display.lineHeight == 1.06)
    #expect(NexusType.Metrics.h1.lineHeight == 1.12)
    #expect(NexusType.Metrics.h2.lineHeight == 1.20)
    #expect(NexusType.Metrics.h3.lineHeight == 1.30)
    #expect(NexusType.Metrics.body.lineHeight == 1.45)
    #expect(NexusType.Metrics.bodySmall.lineHeight == 1.55)
    #expect(NexusType.Metrics.meta.lineHeight == 1.50)
    #expect(NexusType.Metrics.caption.lineHeight == 1.40)
    #expect(NexusType.Metrics.eyebrow.lineHeight == 1.0)
}

@Test func type_metricsAreUnique_acrossSteps() {
    let sizes: Set<Double> = [
        NexusType.Metrics.display.size,
        NexusType.Metrics.h1.size,
        NexusType.Metrics.h2.size,
        NexusType.Metrics.h3.size,
        NexusType.Metrics.body.size,
        NexusType.Metrics.bodySmall.size,
        NexusType.Metrics.meta.size,
        NexusType.Metrics.caption.size,
        NexusType.Metrics.eyebrow.size,
    ]
    #expect(sizes.count == 9, "Each typography step must have a unique size")
}

@Test func type_interFaces_matchWeights() {
    #expect(NexusType.fontName(for: .display) == "Inter-SemiBold")
    #expect(NexusType.fontName(for: .h1) == "Inter-SemiBold")
    #expect(NexusType.fontName(for: .h2) == "Inter-SemiBold")
    #expect(NexusType.fontName(for: .h3) == "Inter-Medium")
    #expect(NexusType.fontName(for: .body) == "Inter-Regular")
    #expect(NexusType.fontName(for: .bodySmall) == "Inter-Regular")
    #expect(NexusType.fontName(for: .meta) == "Inter-Regular")
    #expect(NexusType.fontName(for: .caption) == "Inter-Regular")
    #expect(NexusType.fontName(for: .eyebrow) == "Inter-SemiBold")
}

@Test func type_monoFace_usesIBMPlexMono() {
    #expect(NexusType.monoFontName == "IBMPlexMono-Regular")
}
