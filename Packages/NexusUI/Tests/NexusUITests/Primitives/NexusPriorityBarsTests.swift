import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusPriorityBars v4")
struct NexusPriorityBarsTests {
    @MainActor
    @Test("All levels instantiate")
    func levels() {
        let bars = NexusPriorityLevel.allCases.map(NexusPriorityBars.init)

        #expect(NexusPriorityLevel.allCases == [.zero, .low, .medium, .high, .urgent])

        for bar in bars {
            _ = bar.body
        }
    }

    @MainActor
    @Test("Filled counts match priority levels")
    func filledCounts() {
        let expected: [(NexusPriorityLevel, Int)] = [
            (.zero, 0),
            (.low, 1),
            (.medium, 2),
            (.high, 3),
            (.urgent, 3),
        ]

        for (level, count) in expected {
            let bars = NexusPriorityBars(level)
            let filledCount = (0..<NexusPriorityBars.barHeights.count)
                .filter { bars.isFilled(index: $0) }
                .count

            #expect(filledCount == count)
        }
    }

    @MainActor
    @Test("Urgent uses negative color and other levels use secondary text")
    func activeColors() {
        #expect(NexusPriorityBars(.urgent).activeColor.resolvedRGBA == NexusColor.Text.primary.resolvedRGBA)

        for level in [NexusPriorityLevel.zero, .low, .medium, .high] {
            #expect(NexusPriorityBars(level).activeColor.resolvedRGBA == NexusColor.Text.secondary.resolvedRGBA)
        }
    }

    @MainActor
    @Test("Dimensions match canvas")
    func dimensions() {
        #expect(NexusPriorityBars.barWidth == 2.5)
        #expect(NexusPriorityBars.spacing == 1.5)
        #expect(NexusPriorityBars.frameHeight == 12)
        #expect(NexusPriorityBars.barHeights == [4, 8, 12])
    }

    @MainActor
    @Test("Out of range bar indexes are never filled")
    func outOfRangeIndexes() {
        let bars = NexusPriorityBars(.urgent)

        #expect(!bars.isFilled(index: -1))
        #expect(!bars.isFilled(index: 3))
    }

    @MainActor
    @Test("Accessibility label describes the priority level")
    func accessibilityLabels() {
        #expect(NexusPriorityBars(.zero).accessibilityLabel == "No priority")
        #expect(NexusPriorityBars(.low).accessibilityLabel == "Low priority")
        #expect(NexusPriorityBars(.medium).accessibilityLabel == "Medium priority")
        #expect(NexusPriorityBars(.high).accessibilityLabel == "High priority")
        #expect(NexusPriorityBars(.urgent).accessibilityLabel == "Urgent priority")
    }
}
