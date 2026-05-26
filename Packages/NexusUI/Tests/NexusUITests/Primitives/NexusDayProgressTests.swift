import SwiftUI
import Testing

@testable import NexusUI

@MainActor
@Suite("NexusDayProgress v4")
struct NexusDayProgressTests {
    @Test("Clamps progress to 0..1")
    func clampsProgress() {
        let high = NexusDayProgress(progress: 1.5)
        let low = NexusDayProgress(progress: -0.5)

        #expect(high.progress == 1)
        #expect(low.progress == 0)
    }

    @Test("Clamps tick fractions")
    func clampsTickFractions() {
        let progress = NexusDayProgress(progress: 0.4, tickFractions: [-0.2, 0.3, 1.2])

        #expect(progress.tickFractions == [0, 0.3, 1])
    }

    @Test("Builds captions with counts")
    func buildsCaptions() {
        let progress = NexusDayProgress(
            progress: 0.4,
            tickFractions: [0.1, 0.3, 0.5],
            doneCount: 3,
            totalCount: 12,
            focusedMinutes: 138
        )

        #expect(progress.doneCaption == "3/12 done")
        #expect(progress.focusedCaption == "2h 18m focused")
    }
}
