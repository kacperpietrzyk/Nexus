import SwiftUI
import Testing

@testable import NexusUI

@MainActor
@Suite("NexusTimeRow v4")
struct NexusTimeRowTests {
    @Test("Builds with label and content")
    func builds() {
        let row = NexusTimeRow("09:30") {
            Color.clear
        }

        #expect(row.timeLabel == "09:30")
        #expect(row.isCurrent == false)
    }

    @Test("Builds current row")
    func current() {
        let row = NexusTimeRow("10:00", isCurrent: true) {
            Color.clear
        }

        #expect(row.timeLabel == "10:00")
        #expect(row.isCurrent)
        #expect(NexusTimeRow<EmptyView>.gutterWidth == 48)
    }
}
