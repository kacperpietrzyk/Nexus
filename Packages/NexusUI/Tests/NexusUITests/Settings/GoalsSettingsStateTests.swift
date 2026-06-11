import Foundation
import NexusCore
import Testing

@testable import NexusUI

#if !os(watchOS)

@MainActor
@Test func goalsSettingsState_loadsDefaultsAndPersistsWriteThrough() throws {
    let suiteName = "GoalsSettingsStateTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsGoalsPreferencesStore(defaults: defaults)

    let state = GoalsSettingsState(store: store)
    #expect(state.dailyTarget == 5)
    #expect(state.weeklyTarget == 25)

    state.dailyTarget = 8
    state.weeklyTarget = 0
    #expect(store.load() == GoalsPreferences(dailyCompletionTarget: 8, weeklyCompletionTarget: 0))

    let reloaded = GoalsSettingsState(store: store)
    #expect(reloaded.dailyTarget == 8)
    #expect(reloaded.weeklyTarget == 0)
}

#endif
