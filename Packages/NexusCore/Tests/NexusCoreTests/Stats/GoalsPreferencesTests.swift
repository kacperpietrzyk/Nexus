import Foundation
import Testing

@testable import NexusCore

@Suite struct GoalsPreferencesTests {
    @Test func defaultsAreTodoistKarmaTargets() {
        let preferences = GoalsPreferences.default
        #expect(preferences.dailyCompletionTarget == 5)
        #expect(preferences.weeklyCompletionTarget == 25)
    }

    @Test func storeRoundTripsThroughUserDefaults() throws {
        let suiteName = "GoalsPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsGoalsPreferencesStore(defaults: defaults)

        #expect(store.load() == .default)

        let custom = GoalsPreferences(dailyCompletionTarget: 3, weeklyCompletionTarget: 12)
        store.save(custom)
        #expect(store.load() == custom)
    }

    @Test func corruptPayloadFallsBackToDefault() throws {
        let suiteName = "GoalsPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not json".utf8), forKey: UserDefaultsGoalsPreferencesStore.key)

        let store = UserDefaultsGoalsPreferencesStore(defaults: defaults)
        #expect(store.load() == .default)
    }
}
