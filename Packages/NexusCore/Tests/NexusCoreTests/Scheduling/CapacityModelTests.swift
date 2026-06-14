import Foundation
import Testing

@testable import NexusCore

@Suite struct CapacityModelTests {
    @Test func defaultFromPreferencesIsWorkdaySpanMinusBuffer() {
        var prefs = CalendarPreferences.default  // 09:00–18:00, buffer 0
        prefs.bufferMinutes = 30
        let model = CapacityModel.fromPreferences(prefs)
        // 9h = 540 minutes, minus 30 buffer = 510
        #expect(model.dailyCapacityMinutes == 510)
    }

    @Test func explicitInitClampsToNonNegative() {
        #expect(CapacityModel(dailyCapacityMinutes: -5).dailyCapacityMinutes == 0)
    }
}
