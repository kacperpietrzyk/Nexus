import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("UserDefaultsQuietHoursStore migration")
struct QuietHoursMigrationTests {

    private func makePair() -> (UserDefaults, UserDefaults) {
        let suiteName = "test.nexus.\(UUID().uuidString)"
        let standardName = "test.standard.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        let standard = UserDefaults(suiteName: standardName)!
        return (standard, suite)
    }

    @Test func legacy_value_migrates_to_suite_and_clears_standard() throws {
        let (standard, suite) = makePair()
        let legacy = QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0)
        let data = try JSONEncoder().encode(legacy)
        standard.set(data, forKey: UserDefaultsQuietHoursStore.key)

        UserDefaultsQuietHoursStore.migrate(from: standard, into: suite)

        #expect(suite.data(forKey: UserDefaultsQuietHoursStore.key) == data)
        #expect(standard.data(forKey: UserDefaultsQuietHoursStore.key) == nil)
    }

    @Test func suite_already_populated_is_noop() throws {
        let (standard, suite) = makePair()
        let legacy = QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0)
        let suiteValue = QuietHours(startHour: 23, startMinute: 30, endHour: 6, endMinute: 30)
        standard.set(try JSONEncoder().encode(legacy), forKey: UserDefaultsQuietHoursStore.key)
        suite.set(try JSONEncoder().encode(suiteValue), forKey: UserDefaultsQuietHoursStore.key)

        UserDefaultsQuietHoursStore.migrate(from: standard, into: suite)

        let stored = try JSONDecoder().decode(
            QuietHours.self,
            from: suite.data(forKey: UserDefaultsQuietHoursStore.key)!
        )
        #expect(stored == suiteValue)
        #expect(standard.data(forKey: UserDefaultsQuietHoursStore.key) != nil)
    }

    @Test func no_legacy_value_is_noop() {
        let (standard, suite) = makePair()
        UserDefaultsQuietHoursStore.migrate(from: standard, into: suite)
        #expect(suite.data(forKey: UserDefaultsQuietHoursStore.key) == nil)
    }
}
