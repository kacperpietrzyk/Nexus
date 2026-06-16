import Foundation
import Testing
@testable import NexusMeetings

@Suite struct SummaryProviderPreferenceTests {
    private func store() -> (MeetingsProviderSettingsStore, UserDefaults) {
        let d = UserDefaults(suiteName: "test.summaryPref.\(UUID().uuidString)")!
        return (MeetingsProviderSettingsStore(defaults: d), d)
    }

    @Test func defaultIsAssistantModel() {
        let (s, _) = store()
        #expect(s.summaryProvider() == .assistantModel)
    }

    @Test func legacyAutoMigratesToAssistantModel() {
        let (s, d) = store()
        d.set("auto", forKey: MeetingsSettingsKeys.summaryProvider)
        #expect(s.summaryProvider() == .assistantModel)
    }

    @Test func assistantAndAppleBothRouteAuto() {
        #expect(MeetingsSummaryProviderPreference.assistantModel.providerPreference == .auto)
        #expect(MeetingsSummaryProviderPreference.appleIntelligence.providerPreference == .auto)
        #expect(MeetingsSummaryProviderPreference.disabled.providerPreference == nil)
    }

    @Test func roundTripsExplicitChoice() {
        let (s, _) = store()
        s.saveSummaryProvider(.appleIntelligence)
        #expect(s.summaryProvider() == .appleIntelligence)
    }
}
